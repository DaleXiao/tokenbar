import Foundation

enum AppInfo {
  static let name = "TokenBar"

  static var version: String {
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    switch (shortVersion, build) {
    case let (.some(shortVersion), .some(build)):
      return "\(shortVersion) (\(build))"
    case let (.some(shortVersion), .none):
      return shortVersion
    default:
      return "0.1.0"
    }
  }
}
