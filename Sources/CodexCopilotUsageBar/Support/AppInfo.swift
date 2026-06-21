import Foundation

enum AppInfo {
  static let name = "TokenBar"

  static var shortVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
  }

  static var build: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  }

  static var version: String {
    if let build, !build.isEmpty {
      return "\(shortVersion) (\(build))"
    }
    return shortVersion
  }
}
