import AppKit
import Darwin
import Dispatch
import Foundation

@MainActor
final class UsageLogStore: ObservableObject {
  @Published private(set) var summary = UsageSummary.empty
  @Published private(set) var fileExists = false
  @Published private(set) var statusText = "Loading"
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var invalidLineCount = 0

  @Published private(set) var logFileURL: URL
  @Published private(set) var dataSourceMode: UsageDataSourceMode
  @Published private(set) var dataSourceDescription = "Auto Detect"
  @Published private(set) var activeDataSourceURLs: [URL] = []

  private let watcherQueue = DispatchQueue(label: "com.dingxiao.TokenBar.usage-log-watcher", qos: .utility)
  private let refreshQueue = DispatchQueue(label: "com.dingxiao.TokenBar.usage-log-refresh", qos: .userInitiated)
  nonisolated private static let customLogPathKey = "usageLogPath"
  nonisolated private static let dataSourceModeKey = "usageDataSourceMode"
  private var lastSignature: SourceSignature?
  private var watchers: [DispatchSourceFileSystemObject] = []
  private var fallbackRefreshTimer: DispatchSourceTimer?
  private var refreshGeneration = 0

  init(logFileURL: URL = UsageLogStore.defaultLogURL()) {
    self.logFileURL = logFileURL
    self.dataSourceMode = UsageLogStore.defaultDataSourceMode()
    let loader = UsageDataLoader(dataSourceMode: dataSourceMode, logFileURL: logFileURL)
    if let loaded = loader.loadUsage(force: true, previousSignature: nil) {
      applyLoadedUsage(loaded)
    }
    startWatchingLog()
  }

  deinit {
    watchers.forEach { $0.cancel() }
    fallbackRefreshTimer?.cancel()
  }

  var logPath: String {
    logFileURL.path
  }

  var menuBarTitle: String {
    guard summary.all.requests > 0 else { return "" }
    return UsageFormat.tokens(summary.today.totalTokens)
  }

  func refreshNow() {
    startRefresh(force: true, restartWatching: true)
  }

  func revealDataSource() {
    let urls = activeDataSourceURLs.isEmpty ? [logFileURL] : activeDataSourceURLs
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  func setDataSourceMode(_ mode: UsageDataSourceMode) {
    guard mode != dataSourceMode else { return }
    stopWatchingLog()
    dataSourceMode = mode
    UserDefaults.standard.set(mode.rawValue, forKey: Self.dataSourceModeKey)
    lastSignature = nil
    startRefresh(force: true, restartWatching: true)
  }

  func setLogFileURL(_ url: URL) {
    stopWatchingLog()
    logFileURL = url
    dataSourceMode = .manual
    UserDefaults.standard.set(url.path, forKey: Self.customLogPathKey)
    UserDefaults.standard.set(UsageDataSourceMode.manual.rawValue, forKey: Self.dataSourceModeKey)
    lastSignature = nil
    startRefresh(force: true, restartWatching: true)
  }

  private func refreshIfChanged() {
    startRefresh(force: false, restartWatching: false)
  }

  private func startRefresh(force: Bool, restartWatching: Bool) {
    refreshGeneration += 1
    let generation = refreshGeneration
    let mode = dataSourceMode
    let url = logFileURL
    let previousSignature = lastSignature

    statusText = "Refreshing"
    refreshQueue.async { [weak self] in
      let loader = UsageDataLoader(dataSourceMode: mode, logFileURL: url)
      let loaded = loader.loadUsage(force: force, previousSignature: previousSignature)
      Task { @MainActor in
        guard let self, self.refreshGeneration == generation else { return }
        if let loaded {
          self.applyLoadedUsage(loaded)
        } else {
          self.restoreStatusAfterNoChange()
        }
        if restartWatching {
          self.startWatchingLog()
        }
      }
    }
  }

  private func applyLoadedUsage(_ loaded: LoadedUsage) {
    lastSignature = loaded.signature
    fileExists = loaded.hasSources
    activeDataSourceURLs = loaded.sourceURLs
    dataSourceDescription = loaded.description
    lastRefreshDate = Date()

    guard loaded.hasSources else {
      summary = .empty
      invalidLineCount = 0
      statusText = "Waiting for data source"
      return
    }

    summary = UsageSummary(records: loaded.records)
    invalidLineCount = loaded.invalidLines
    statusText = loaded.invalidLines == 0 ? "Live" : "Live, skipped \(loaded.invalidLines)"
  }

  private func restoreStatusAfterNoChange() {
    guard statusText == "Refreshing" else { return }
    statusText = fileExists
      ? (invalidLineCount == 0 ? "Live" : "Live, skipped \(invalidLineCount)")
      : "Waiting for data source"
  }

  private func startWatchingLog() {
    stopWatchingLog()

    var startedWatcher = false
    for target in watchTargets().prefix(16) {
      startedWatcher = startWatcher(for: target) || startedWatcher
    }

    if dataSourceMode == .automatic || !startedWatcher {
      startFallbackRefreshTimer()
    }
  }

  private func stopWatchingLog() {
    watchers.forEach { $0.cancel() }
    watchers.removeAll()
    fallbackRefreshTimer?.cancel()
    fallbackRefreshTimer = nil
  }

  private func startWatcher(for url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    guard exists else { return false }

    let descriptor = open(url.path, O_EVTONLY)
    guard descriptor >= 0 else { return false }

    let eventMask: DispatchSource.FileSystemEvent = isDirectory.boolValue
      ? [.write, .delete, .rename]
      : [.write, .extend, .delete, .rename, .revoke]
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: eventMask,
      queue: watcherQueue
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.handleSourceEvent()
      }
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    watchers.append(source)
    return true
  }

  private func startFallbackRefreshTimer() {
    let timer = DispatchSource.makeTimerSource(queue: watcherQueue)
    timer.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30), leeway: .seconds(10))
    timer.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.handleFallbackRefresh()
      }
    }
    timer.resume()
    fallbackRefreshTimer = timer
  }

  private func handleSourceEvent() {
    refreshIfChanged()
    startWatchingLog()
  }

  private func handleFallbackRefresh() {
    refreshIfChanged()
    if fileExists {
      startWatchingLog()
    }
  }

  private func watchTargets() -> [URL] {
    switch dataSourceMode {
    case .automatic:
      return UsageDataLoader.automaticSources().map(\.url)
    case .manual:
      if logFileURL.exists {
        return [logFileURL]
      }
      return [logFileURL.deletingLastPathComponent()]
    }
  }

  nonisolated private static func defaultDataSourceMode() -> UsageDataSourceMode {
    if let rawValue = UserDefaults.standard.string(forKey: dataSourceModeKey),
      let mode = UsageDataSourceMode(rawValue: rawValue)
    {
      return mode
    }
    return .automatic
  }

  nonisolated private static func defaultLogURL() -> URL {
    if let configuredPath = UserDefaults.standard.string(forKey: customLogPathKey), !configuredPath.isEmpty {
      return URL(fileURLWithPath: expandTilde(configuredPath))
    }
    if let configuredPath = ProcessInfo.processInfo.environment["CCDX_USAGE_PATH"], !configuredPath.isEmpty {
      return URL(fileURLWithPath: expandTilde(configuredPath))
    }
    return codexCopilotDXLogURL()
  }

  nonisolated private static func codexCopilotDXLogURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local")
      .appendingPathComponent("share")
      .appendingPathComponent("codex-copilot-dx")
      .appendingPathComponent("usage.jsonl")
  }

  nonisolated private static func expandTilde(_ path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else {
      return path
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == "~" {
      return home
    }
    return home + String(path.dropFirst())
  }
}

private struct UsageDataLoader {
  private let dataSourceMode: UsageDataSourceMode
  private let logFileURL: URL
  private let decoder = JSONDecoder()
  private let codexCopilotDXMaxBytes = 24 * 1024 * 1024
  private let automaticDirectoryMaxFiles = 60
  private let automaticDirectoryMaxBytesPerFile = 512 * 1024
  private let manualDirectoryMaxFiles = 120
  private let manualMaxBytesPerFile = 8 * 1024 * 1024
  private let codexModelHintMaxBytes = 1024 * 1024
  private let codexSessionSnapshotMaxBytes = 1024 * 1024

  init(dataSourceMode: UsageDataSourceMode, logFileURL: URL) {
    self.dataSourceMode = dataSourceMode
    self.logFileURL = logFileURL
  }

  func loadUsage(force: Bool, previousSignature: SourceSignature?) -> LoadedUsage? {
    let sources = currentSources()
    let signature = SourceSignature(files: sources.flatMap(signatureEntries(for:)).sorted { $0.path < $1.path })
    if !force, signature == previousSignature {
      return nil
    }

    var records: [UsageRecord] = []
    var invalidLines = 0
    var activeTitles: [String] = []
    var activeURLs: [URL] = []

    for source in sources where source.exists {
      let parsed = parseRecords(from: source)
      records.append(contentsOf: parsed.records)
      invalidLines += parsed.invalidLines
      activeTitles.append(source.title)
      activeURLs.append(source.url)
    }

    return LoadedUsage(
      records: records,
      invalidLines: invalidLines,
      hasSources: !activeURLs.isEmpty,
      sourceURLs: activeURLs,
      description: dataSourceDescription(for: activeTitles),
      signature: signature
    )
  }

  private func currentSources() -> [UsageSource] {
    switch dataSourceMode {
    case .automatic:
      return Self.automaticSources()
    case .manual:
      return [UsageSource(title: "Selected Path", kind: .autoDetect, url: logFileURL)]
    }
  }

  static func automaticSources() -> [UsageSource] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      UsageSource(title: "Codex", kind: .codexSessions, url: home.appendingPathComponent(".codex/sessions")),
      UsageSource(title: "Claude Code", kind: .claudeProjects, url: home.appendingPathComponent(".claude/projects"))
    ].filter(\.exists)
  }

  private func dataSourceDescription(for titles: [String]) -> String {
    guard !titles.isEmpty else {
      return dataSourceMode == .automatic ? "Auto Detect: No supported agents found" : "Selected Path: Not found"
    }

    switch dataSourceMode {
    case .automatic:
      return "Auto: \(titles.joined(separator: ", "))"
    case .manual:
      return "Manual: \(logFileURL.lastPathComponent)"
    }
  }

  private func parseRecords(from source: UsageSource) -> (records: [UsageRecord], invalidLines: Int) {
    var records: [UsageRecord] = []
    var invalidLines = 0

    for fileURL in jsonlFiles(for: source) {
      var codexModelNameHint = initialCodexModelHint(for: fileURL, source: source)
      let readLimit = readLimit(for: source, fileURL: fileURL)

      if source.kind == .codexSessions {
        let parsed = parseCodexSessionSnapshot(
          from: fileURL,
          initialModelHint: codexModelNameHint
        )
        records.append(contentsOf: parsed.records)
        invalidLines += parsed.invalidLines
        continue
      }

      guard let data = readBoundedData(from: fileURL, limit: readLimit) else {
        invalidLines += 1
        continue
      }
      let text = String(decoding: data, as: UTF8.self)

      for line in text.split(whereSeparator: \.isNewline) {
        let lineText = String(line)
        guard let lineData = lineText.data(using: .utf8) else {
          invalidLines += 1
          continue
        }
        if source.kind.supportsCodexModelHints,
          (lineText.contains(#""turn_context""#) || lineText.contains(#""session_meta""#)),
          let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
          let hint = codexModelHint(from: object)
        {
          codexModelNameHint = hint
        }
        switch parseLine(lineData, sourceKind: source.kind, codexModelHint: codexModelNameHint) {
        case let .record(record):
          records.append(record)
        case .ignored:
          break
        case .invalid:
          invalidLines += 1
        }
      }
    }

    return (records, invalidLines)
  }

  private func parseCodexSessionSnapshot(
    from fileURL: URL,
    initialModelHint: String?
  ) -> (records: [UsageRecord], invalidLines: Int) {
    guard let data = readBoundedData(from: fileURL, limit: codexSessionSnapshotMaxBytes) else {
      return ([], 1)
    }

    var invalidLines = 0
    var modelHint = initialModelHint
    var latestTimestamp: String?
    var latestModel: String?
    var latestTotalValues: [String: Double]?

    for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
      guard let lineData = String(line).data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
      else {
        invalidLines += 1
        continue
      }

      if let hint = codexModelHint(from: object) {
        modelHint = hint
      }

      guard object["type"] as? String == "event_msg",
        let payload = object["payload"] as? [String: Any],
        payload["type"] as? String == "token_count",
        let info = payload["info"] as? [String: Any],
        let totalUsageObject = info["total_token_usage"] as? [String: Any]
      else {
        continue
      }

      let totalValues = numericValues(in: totalUsageObject)
      guard !totalValues.isEmpty, totalValues.values.contains(where: { $0 != 0 }) else { continue }
      latestTimestamp = timestamp(from: object)
      latestModel = info["model"] as? String
      latestTotalValues = totalValues
    }

    guard let latestTotalValues else {
      return ([], invalidLines)
    }

    return ([
      UsageRecord(
        timestamp: codexSessionRecordTimestamp(for: fileURL, latestTimestamp: latestTimestamp),
        surface: "codex",
        mode: "session",
        model: latestModel ?? modelHint,
        responseID: fileURL.lastPathComponent,
        usage: TokenUsage(values: latestTotalValues),
        copilotUsage: nil
      )
    ], invalidLines)
  }

  private func parseLine(_ data: Data, sourceKind: UsageSourceKind, codexModelHint: String?) -> ParsedUsageLine {
    if let record = try? decoder.decode(UsageRecord.self, from: data) {
      return .record(record)
    }

    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return .invalid
    }

    let record: UsageRecord?
    switch sourceKind {
    case .codexCopilotDX:
      record = decodeCodexTokenCount(from: object, modelHint: codexModelHint)
        ?? decodeCodexExecRecord(from: object, modelHint: codexModelHint)
        ?? decodeClaudeRecord(from: object)
    case .codexSessions:
      record = decodeCodexTokenCount(from: object, modelHint: codexModelHint)
        ?? decodeCodexExecRecord(from: object, modelHint: codexModelHint)
    case .claudeProjects:
      record = decodeClaudeRecord(from: object)
    case .autoDetect:
      record = decodeCodexTokenCount(from: object, modelHint: codexModelHint)
        ?? decodeCodexExecRecord(from: object, modelHint: codexModelHint)
        ?? decodeClaudeRecord(from: object)
    }
    return record.map(ParsedUsageLine.record) ?? .ignored
  }

  private func decodeCodexTokenCount(from object: [String: Any], modelHint: String?) -> UsageRecord? {
    guard object["type"] as? String == "event_msg",
      let payload = object["payload"] as? [String: Any],
      payload["type"] as? String == "token_count",
      let info = payload["info"] as? [String: Any],
      let usageObject = info["last_token_usage"] as? [String: Any]
    else {
      return nil
    }

    let values = numericValues(in: usageObject)
    guard !values.isEmpty, values.values.contains(where: { $0 != 0 }) else { return nil }

    return UsageRecord(
      timestamp: timestamp(from: object) ?? currentTimestamp(),
      surface: "codex",
      mode: "session",
      model: info["model"] as? String ?? modelHint,
      responseID: object["id"] as? String,
      usage: TokenUsage(values: values),
      copilotUsage: nil
    )
  }

  private func decodeCodexExecRecord(from object: [String: Any], modelHint: String?) -> UsageRecord? {
    guard object["type"] as? String == "turn.completed",
      let usageObject = object["usage"] as? [String: Any]
    else {
      return nil
    }

    let values = numericValues(in: usageObject)
    guard !values.isEmpty, values.values.contains(where: { $0 != 0 }) else { return nil }

    return UsageRecord(
      timestamp: timestamp(from: object) ?? currentTimestamp(),
      surface: "codex",
      mode: "exec",
      model: object["model"] as? String ?? modelHint,
      responseID: object["thread_id"] as? String,
      usage: TokenUsage(values: values),
      copilotUsage: nil
    )
  }

  private func decodeClaudeRecord(from object: [String: Any]) -> UsageRecord? {
    guard let message = object["message"] as? [String: Any],
      let usageObject = message["usage"] as? [String: Any]
    else {
      return nil
    }

    let values = numericValues(in: usageObject)
    guard !values.isEmpty, values.values.contains(where: { $0 != 0 }) else { return nil }

    return UsageRecord(
      timestamp: timestamp(from: object) ?? currentTimestamp(),
      surface: "claude-code",
      mode: object["entrypoint"] as? String,
      model: message["model"] as? String,
      responseID: message["id"] as? String ?? object["uuid"] as? String,
      usage: TokenUsage(values: values),
      copilotUsage: nil
    )
  }

  private func numericValues(in object: [String: Any]) -> [String: Double] {
    var values: [String: Double] = [:]
    for (key, value) in object {
      if value is Bool {
        continue
      }
      if let number = value as? NSNumber {
        let double = number.doubleValue
        if double.isFinite {
          values[key] = double
        }
      }
    }
    return values
  }

  private func timestamp(from object: [String: Any]) -> String? {
    object["timestamp"] as? String ?? object["ts"] as? String
  }

  private func currentTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }

  private func initialCodexModelHint(for fileURL: URL, source: UsageSource) -> String? {
    guard source.kind.supportsCodexModelHints,
      let data = readHeadData(from: fileURL, limit: codexModelHintMaxBytes)
    else {
      return nil
    }

    let text = String(decoding: data, as: UTF8.self)
    for line in text.split(whereSeparator: \.isNewline) {
      guard line.contains(#""turn_context""#) || line.contains(#""session_meta""#),
        let lineData = String(line).data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let hint = codexModelHint(from: object)
      else {
        continue
      }
      return hint
    }
    return nil
  }

  private func codexModelHint(from object: [String: Any]) -> String? {
    guard let payload = object["payload"] as? [String: Any],
      object["type"] as? String == "turn_context" || object["type"] as? String == "session_meta"
    else {
      return nil
    }

    if let model = payload["model"] as? String, !model.isEmpty {
      return model
    }
    if let collaborationMode = payload["collaboration_mode"] as? [String: Any],
      let settings = collaborationMode["settings"] as? [String: Any],
      let model = settings["model"] as? String,
      !model.isEmpty
    {
      return model
    }
    return nil
  }

  private func jsonlFiles(for source: UsageSource) -> [URL] {
    if source.isDirectory {
      return jsonlFiles(in: source.url, limit: fileLimit(for: source))
    }
    guard source.url.pathExtension.lowercased() == "jsonl" || source.kind == .autoDetect else {
      return []
    }
    return source.url.exists ? [source.url] : []
  }

  private func jsonlFiles(in directoryURL: URL, limit: Int) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: directoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: [.skipsPackageDescendants]
    ) else {
      return []
    }

    var files: [(url: URL, modifiedAt: Date)] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "jsonl" {
      let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
      files.append((url: fileURL, modifiedAt: values?.contentModificationDate ?? .distantPast))
    }
    return files
      .sorted {
        if $0.modifiedAt == $1.modifiedAt {
          return $0.url.path > $1.url.path
        }
        return $0.modifiedAt > $1.modifiedAt
      }
      .prefix(limit)
      .map(\.url)
      .sorted { $0.path < $1.path }
  }

  private func signatureEntries(for source: UsageSource) -> [FileSignature] {
    var entries: [FileSignature] = []
    if let signature = fileSignature(for: source.url) {
      entries.append(signature)
    }
    if source.isDirectory {
      entries.append(contentsOf: jsonlFiles(for: source).compactMap(fileSignature(for:)))
    }
    return entries
  }

  private func fileLimit(for source: UsageSource) -> Int {
    if dataSourceMode == .manual {
      return manualDirectoryMaxFiles
    }
    switch source.kind {
    case .codexCopilotDX:
      return 1
    case .codexSessions, .claudeProjects, .autoDetect:
      return automaticDirectoryMaxFiles
    }
  }

  private func readLimit(for source: UsageSource, fileURL: URL) -> Int {
    if dataSourceMode == .manual {
      return manualMaxBytesPerFile
    }
    switch source.kind {
    case .codexCopilotDX:
      return codexCopilotDXMaxBytes
    case .codexSessions:
      return codexSessionSnapshotMaxBytes
    case .claudeProjects, .autoDetect:
      return automaticDirectoryMaxBytesPerFile
    }
  }

  private func isCodexSessionPathToday(_ url: URL) -> Bool {
    let components = url.pathComponents
    guard let dayIndex = components.indices.dropLast().last,
      dayIndex >= 2,
      let year = Int(components[dayIndex - 2]),
      let month = Int(components[dayIndex - 1]),
      let day = Int(components[dayIndex])
    else {
      return false
    }

    let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return today.year == year && today.month == month && today.day == day
  }

  private func codexSessionRecordTimestamp(for url: URL, latestTimestamp: String?) -> String {
    if isCodexSessionPathToday(url), let latestTimestamp {
      return latestTimestamp
    }
    if let pathDate = codexSessionPathDate(from: url) {
      return ISO8601DateFormatter().string(from: pathDate)
    }
    return latestTimestamp ?? currentTimestamp()
  }

  private func codexSessionPathDate(from url: URL) -> Date? {
    let components = url.pathComponents
    guard let dayIndex = components.indices.dropLast().last,
      dayIndex >= 2,
      let year = Int(components[dayIndex - 2]),
      let month = Int(components[dayIndex - 1]),
      let day = Int(components[dayIndex])
    else {
      return nil
    }
    return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
  }

  private func readBoundedData(from url: URL, limit: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer {
      try? handle.close()
    }

    guard let endOffset = try? handle.seekToEnd() else { return nil }
    let limitOffset = UInt64(max(limit, 0))
    let startOffset = endOffset > limitOffset ? endOffset - limitOffset : 0
    do {
      try handle.seek(toOffset: startOffset)
      var data = try handle.readToEnd() ?? Data()
      if startOffset > 0, let firstNewline = data.firstIndex(of: 10) {
        data.removeSubrange(data.startIndex...firstNewline)
      }
      return data
    } catch {
      return nil
    }
  }

  private func readHeadData(from url: URL, limit: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer {
      try? handle.close()
    }

    return try? handle.read(upToCount: max(limit, 0)) ?? Data()
  }

  private func fileSignature(for url: URL) -> FileSignature? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
      let modifiedAt = attributes[.modificationDate] as? Date
      return FileSignature(path: url.path, size: size, modifiedAt: modifiedAt)
    } catch {
      return nil
    }
  }
}

private struct LoadedUsage {
  let records: [UsageRecord]
  let invalidLines: Int
  let hasSources: Bool
  let sourceURLs: [URL]
  let description: String
  let signature: SourceSignature
}

private struct UsageSource {
  let title: String
  let kind: UsageSourceKind
  let url: URL

  var exists: Bool {
    url.exists
  }

  var isDirectory: Bool {
    url.isDirectory
  }
}

private enum UsageSourceKind {
  case codexCopilotDX
  case codexSessions
  case claudeProjects
  case autoDetect

  var supportsCodexModelHints: Bool {
    switch self {
    case .codexCopilotDX, .codexSessions, .autoDetect:
      return true
    case .claudeProjects:
      return false
    }
  }
}

private enum ParsedUsageLine {
  case record(UsageRecord)
  case ignored
  case invalid
}

private struct SourceSignature: Equatable {
  let files: [FileSignature]
}

private struct FileSignature: Equatable {
  let path: String
  let size: UInt64
  let modifiedAt: Date?
}

private extension URL {
  var exists: Bool {
    FileManager.default.fileExists(atPath: path)
  }

  var isDirectory: Bool {
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
  }
}
