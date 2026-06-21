import Foundation

enum UsageDateParser {
  static func date(from string: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) {
      return date
    }

    let standard = ISO8601DateFormatter()
    return standard.date(from: string)
  }
}
