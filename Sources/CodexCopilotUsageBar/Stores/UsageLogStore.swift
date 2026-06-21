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

  private let watcherQueue = DispatchQueue(label: "com.dingxiao.TokenBar.usage-log-watcher", qos: .utility)
  private let decoder = JSONDecoder()
  nonisolated private static let customLogPathKey = "usageLogPath"
  private var lastSignature: FileSignature?
  private var fileWatcher: DispatchSourceFileSystemObject?
  private var directoryWatcher: DispatchSourceFileSystemObject?
  private var fallbackRefreshTimer: DispatchSourceTimer?

  init(logFileURL: URL = UsageLogStore.defaultLogURL()) {
    self.logFileURL = logFileURL
    refresh(force: true)
    startWatchingLog()
  }

  deinit {
    fileWatcher?.cancel()
    directoryWatcher?.cancel()
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
    refresh(force: true)
    startWatchingLog()
  }

  func revealLog() {
    NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
  }

  func setLogFileURL(_ url: URL) {
    guard url != logFileURL else { return }
    stopWatchingLog()
    logFileURL = url
    UserDefaults.standard.set(url.path, forKey: Self.customLogPathKey)
    lastSignature = nil
    refresh(force: true)
    startWatchingLog()
  }

  private func refreshIfChanged() {
    refresh(force: false)
  }

  private func startWatchingLog() {
    stopWatchingLog()

    if fileSignature() != nil {
      if !startFileWatcher() {
        startFallbackRefreshTimer()
      }
      return
    }

    if !startDirectoryWatcher() {
      startFallbackRefreshTimer()
    }
  }

  private func stopWatchingLog() {
    fileWatcher?.cancel()
    fileWatcher = nil
    directoryWatcher?.cancel()
    directoryWatcher = nil
    fallbackRefreshTimer?.cancel()
    fallbackRefreshTimer = nil
  }

  private func startFileWatcher() -> Bool {
    let descriptor = open(logFileURL.path, O_EVTONLY)
    guard descriptor >= 0 else {
      return false
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .delete, .rename, .revoke],
      queue: watcherQueue
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.handleLogFileEvent()
      }
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    fileWatcher = source
    return true
  }

  private func startDirectoryWatcher() -> Bool {
    let directoryURL = logFileURL.deletingLastPathComponent()
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return false
    }

    let descriptor = open(directoryURL.path, O_EVTONLY)
    guard descriptor >= 0 else {
      return false
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename],
      queue: watcherQueue
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.handleDirectoryEvent()
      }
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    directoryWatcher = source
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

  private func handleLogFileEvent() {
    refreshIfChanged()
    if fileSignature() == nil {
      startWatchingLog()
    }
  }

  private func handleDirectoryEvent() {
    refreshIfChanged()
    startWatchingLog()
  }

  private func handleFallbackRefresh() {
    refreshIfChanged()
    if fileSignature() != nil {
      startWatchingLog()
    }
  }

  private func refresh(force: Bool) {
    let signature = fileSignature()
    if !force, signature == lastSignature {
      return
    }
    lastSignature = signature

    guard signature != nil else {
      fileExists = false
      summary = .empty
      invalidLineCount = 0
      statusText = "Waiting for log"
      lastRefreshDate = Date()
      return
    }

    fileExists = true

    do {
      let data = try Data(contentsOf: logFileURL)
      let text = String(decoding: data, as: UTF8.self)
      let parsed = parseRecords(from: text)
      summary = UsageSummary(records: parsed.records)
      invalidLineCount = parsed.invalidLines
      lastRefreshDate = Date()
      statusText = parsed.invalidLines == 0 ? "Live" : "Live, skipped \(parsed.invalidLines)"
    } catch {
      statusText = error.localizedDescription
      lastRefreshDate = Date()
    }
  }

  private func parseRecords(from text: String) -> (records: [UsageRecord], invalidLines: Int) {
    var records: [UsageRecord] = []
    var invalidLines = 0

    for line in text.split(whereSeparator: \.isNewline) {
      guard let data = String(line).data(using: .utf8) else {
        invalidLines += 1
        continue
      }
      do {
        records.append(try decoder.decode(UsageRecord.self, from: data))
      } catch {
        invalidLines += 1
      }
    }

    return (records, invalidLines)
  }

  private func fileSignature() -> FileSignature? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
      let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
      let modifiedAt = attributes[.modificationDate] as? Date
      return FileSignature(size: size, modifiedAt: modifiedAt)
    } catch {
      return nil
    }
  }

  nonisolated private static func defaultLogURL() -> URL {
    if let configuredPath = UserDefaults.standard.string(forKey: customLogPathKey), !configuredPath.isEmpty {
      return URL(fileURLWithPath: expandTilde(configuredPath))
    }
    if let configuredPath = ProcessInfo.processInfo.environment["CCDX_USAGE_PATH"], !configuredPath.isEmpty {
      return URL(fileURLWithPath: expandTilde(configuredPath))
    }
    return FileManager.default.homeDirectoryForCurrentUser
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

private struct FileSignature: Equatable {
  let size: UInt64
  let modifiedAt: Date?
}
