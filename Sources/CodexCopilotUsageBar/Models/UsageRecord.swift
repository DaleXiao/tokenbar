import Foundation

private let agentModelPlaceholders: Set<String> = [
  "agent",
  "auto",
  "claude",
  "claude code",
  "claude-code",
  "codex",
  "codex app",
  "codex-app",
  "codex cli",
  "codex-cli",
  "codex-copilot-dx",
  "manual",
  "session",
  "unknown"
]

struct UsageRecord: Decodable {
  let timestamp: String
  let surface: String?
  let mode: String?
  let model: String?
  let responseID: String?
  let usage: TokenUsage?
  let copilotUsage: TokenUsage?

  init(
    timestamp: String,
    surface: String?,
    mode: String?,
    model: String?,
    responseID: String?,
    usage: TokenUsage?,
    copilotUsage: TokenUsage?
  ) {
    self.timestamp = timestamp
    self.surface = surface
    self.mode = mode
    self.model = model
    self.responseID = responseID
    self.usage = usage
    self.copilotUsage = copilotUsage
  }

  enum CodingKeys: String, CodingKey {
    case timestamp = "ts"
    case surface
    case mode
    case model
    case responseID = "response_id"
    case usage
    case copilotUsage = "copilot_usage"
  }

  var date: Date? {
    UsageDateParser.date(from: timestamp)
  }

  var modelDisplayName: String? {
    guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines),
      !model.isEmpty
    else {
      return nil
    }

    let lowercased = model.lowercased()
    guard !agentModelPlaceholders.contains(lowercased) else { return nil }

    if lowercased.hasPrefix("gpt-")
      || lowercased.hasPrefix("claude-")
      || lowercased.hasPrefix("gemini-")
      || lowercased.hasPrefix("deepseek-")
      || lowercased.hasPrefix("qwen")
      || lowercased.hasPrefix("kimi")
      || lowercased.hasPrefix("llama")
      || lowercased.hasPrefix("mistral-")
      || lowercased.hasPrefix("mixtral-")
      || lowercased.hasPrefix("grok-")
      || lowercased.hasPrefix("command-")
      || lowercased.hasPrefix("codestral-")
      || lowercased.hasPrefix("devstral-")
      || lowercased.hasPrefix("glm-")
      || lowercased.contains("/")
      || lowercased.range(of: #"^o[1-9]([.-].*)?$"#, options: .regularExpression) != nil
    {
      return model
    }

    return nil
  }

  var agentDisplayName: String {
    let lowercasedSurface = surface?.lowercased() ?? ""
    let lowercasedMode = mode?.lowercased() ?? ""

    if lowercasedSurface.contains("copilot") {
      return "codex-copilot-dx"
    }
    if lowercasedSurface.contains("claude") || lowercasedMode.contains("claude") {
      return "Claude Code"
    }
    if lowercasedSurface.contains("codex") || lowercasedMode.contains("codex") {
      return lowercasedMode == "exec" ? "Codex CLI" : "Codex App"
    }

    if let surface, !surface.isEmpty {
      return formattedAgentName(surface)
    }
    if let mode, !mode.isEmpty {
      return formattedAgentName(mode)
    }
    return "Unknown Agent"
  }

  var isCodexSessionTotal: Bool {
    surface?.lowercased() == "codex" && mode?.lowercased() == "session-total"
  }

  var isCodexSessionDelta: Bool {
    surface?.lowercased() == "codex" && mode?.lowercased() == "session-delta"
  }
}

struct TokenUsage: Decodable {
  let values: [String: Double]

  init(values: [String: Double]) {
    self.values = values
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    var decoded: [String: Double] = [:]
    for key in container.allKeys {
      if let value = try? container.decode(Double.self, forKey: key), value.isFinite {
        decoded[key.stringValue] = value
      }
    }
    values = decoded
  }

  var inputTokens: Double {
    values["input_tokens"] ?? 0
  }

  var cachedTokens: Double {
    values["cached_input_tokens"]
      ?? values["cache_read_input_tokens"]
      ?? values["cache_read_tokens"]
      ?? 0
  }

  var outputTokens: Double {
    values["output_tokens"] ?? 0
  }

  var totalTokens: Double {
    if let total = values["total_tokens"] {
      return total
    }
    if values["cache_read_input_tokens"] != nil || values["cache_creation_input_tokens"] != nil {
      return inputTokens
        + cachedTokens
        + (values["cache_creation_input_tokens"] ?? 0)
        + outputTokens
    }
    return inputTokens + outputTokens
  }

  var nanoAIU: Double {
    values["total_nano_aiu"] ?? 0
  }

  var estimatedNanoAIU: Double {
    let billableInputTokens = max(0, inputTokens - cachedTokens)
    return billableInputTokens * 250_000
      + cachedTokens * 25_000
      + outputTokens * 1_500_000
  }
}

struct UsageTotals {
  var requests = 0
  var inputTokens = 0.0
  var cachedTokens = 0.0
  var outputTokens = 0.0
  var totalTokens = 0.0
  var nanoAIU = 0.0

  mutating func add(_ record: UsageRecord) {
    if let usage = record.usage {
      requests += 1
      inputTokens += usage.inputTokens
      cachedTokens += usage.cachedTokens
      outputTokens += usage.outputTokens
      totalTokens += usage.totalTokens
    }
    if let copilotUsage = record.copilotUsage, copilotUsage.nanoAIU > 0 {
      nanoAIU += copilotUsage.nanoAIU
    } else if let usage = record.usage {
      nanoAIU += usage.estimatedNanoAIU
    }
  }
}

struct ModelUsage: Identifiable {
  let model: String
  var totals: UsageTotals

  var id: String { model }
}

struct AgentUsage: Identifiable {
  let agent: String
  var totals: UsageTotals

  var id: String { agent }
}

struct UsageSummary {
  var all = UsageTotals()
  var today = UsageTotals()
  var byModel: [ModelUsage] = []
  var byAgent: [AgentUsage] = []

  static let empty = UsageSummary()

  init() {}

  init(records: [UsageRecord], calendar: Calendar = .current) {
    var all = UsageTotals()
    var today = UsageTotals()
    var models: [String: UsageTotals] = [:]
    var agents: [String: UsageTotals] = [:]

    for record in records {
      if !record.isCodexSessionDelta {
        all.add(record)
      }
      if !record.isCodexSessionTotal, let date = record.date, calendar.isDateInToday(date) {
        today.add(record)
      }
      guard record.usage != nil, !record.isCodexSessionDelta else { continue }
      if let model = record.modelDisplayName {
        models[model, default: UsageTotals()].add(record)
      }
      agents[record.agentDisplayName, default: UsageTotals()].add(record)
    }

    self.all = all
    self.today = today
    self.byModel = models
      .map { ModelUsage(model: $0.key, totals: $0.value) }
      .sorted { lhs, rhs in
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
          return lhs.model < rhs.model
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
      }
    self.byAgent = agents
      .map { AgentUsage(agent: $0.key, totals: $0.value) }
      .sorted { lhs, rhs in
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
          return lhs.agent < rhs.agent
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
      }
  }
}

private func formattedAgentName(_ rawValue: String) -> String {
  rawValue
    .split { $0 == "-" || $0 == "_" || $0 == "." }
    .map { word in
      guard let first = word.first else { return "" }
      return first.uppercased() + String(word.dropFirst())
    }
    .joined(separator: " ")
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}
