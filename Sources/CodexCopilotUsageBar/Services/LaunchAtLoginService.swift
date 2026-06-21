import Foundation

enum LaunchAtLoginService {
  private static let label = "com.dingxiao.TokenBar"

  static var isEnabled: Bool {
    FileManager.default.fileExists(atPath: launchAgentURL.path)
  }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try enable()
    } else {
      try disable()
    }
  }

  private static func enable() throws {
    try FileManager.default.createDirectory(
      at: launchAgentURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let plist: [String: Any] = [
      "Label": label,
      "ProgramArguments": ["/usr/bin/open", "-n", Bundle.main.bundlePath],
      "RunAtLoad": true
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: launchAgentURL, options: .atomic)
    _ = runLaunchctl(arguments: ["bootout", domain, launchAgentURL.path])
    let result = runLaunchctl(arguments: ["bootstrap", domain, launchAgentURL.path])
    if result.exitCode != 0 {
      throw LaunchAtLoginError.launchctl(result.errorText)
    }
  }

  private static func disable() throws {
    _ = runLaunchctl(arguments: ["bootout", domain, launchAgentURL.path])
    if FileManager.default.fileExists(atPath: launchAgentURL.path) {
      try FileManager.default.removeItem(at: launchAgentURL)
    }
  }

  private static var launchAgentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("LaunchAgents")
      .appendingPathComponent("\(label).plist")
  }

  private static var domain: String {
    "gui/\(getuid())"
  }

  private static func runLaunchctl(arguments: [String]) -> (exitCode: Int32, errorText: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments

    let errorPipe = Pipe()
    process.standardError = errorPipe

    do {
      try process.run()
      process.waitUntilExit()
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    } catch {
      return (1, error.localizedDescription)
    }
  }
}

enum LaunchAtLoginError: LocalizedError {
  case launchctl(String)

  var errorDescription: String? {
    switch self {
    case let .launchctl(message):
      return message.isEmpty ? "launchctl failed." : message
    }
  }
}
