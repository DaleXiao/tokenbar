import Foundation

struct UsageRecord: Decodable {
  let timestamp: String
  let surface: String?
  let mode: String?
  let model: String?
  let responseID: String?
  let usage: TokenUsage?
  let copilotUsage: TokenUsage?

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
}

struct TokenUsage: Decodable {
  let values: [String: Double]

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
}

struct UsageTotals {
  var requests = 0
  var inputTokens = 0.0
  var cachedTokens = 0.0
  var outputTokens = 0.0
  var totalTokens = 0.0
  var nanoAIU = 0.0

  mutating func add(_ record: UsageRecord) {
    requests += 1
    if let usage = record.usage {
      inputTokens += usage.inputTokens
      cachedTokens += usage.cachedTokens
      outputTokens += usage.outputTokens
      totalTokens += usage.totalTokens
    }
    if let copilotUsage = record.copilotUsage {
      nanoAIU += copilotUsage.nanoAIU
    }
  }
}

struct ModelUsage: Identifiable {
  let model: String
  var totals: UsageTotals

  var id: String { model }
}

struct UsageSummary {
  var all = UsageTotals()
  var today = UsageTotals()
  var byModel: [ModelUsage] = []
  var recent: [UsageRecord] = []

  static let empty = UsageSummary()

  init() {}

  init(records: [UsageRecord], calendar: Calendar = .current) {
    var all = UsageTotals()
    var today = UsageTotals()
    var models: [String: UsageTotals] = [:]

    for record in records {
      all.add(record)
      if let date = record.date, calendar.isDateInToday(date) {
        today.add(record)
      }
      let model = record.model ?? "unknown"
      models[model, default: UsageTotals()].add(record)
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
    self.recent = Array(records.suffix(5).reversed())
  }
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
