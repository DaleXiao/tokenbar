import Foundation

enum UsageFormat {
  static func tokens(_ value: Double) -> String {
    abbreviated(value, suffix: "")
  }

  static func aiu(fromNano value: Double) -> String {
    abbreviated(value / 1_000_000_000, suffix: "")
  }

  static func integer(_ value: Int) -> String {
    numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  static func time(_ date: Date?) -> String {
    guard let date else { return "--" }
    return timeFormatter.string(from: date)
  }

  static func dateTime(_ date: Date?) -> String {
    guard let date else { return "--" }
    return dateTimeFormatter.string(from: date)
  }

  private static func abbreviated(_ value: Double, suffix: String) -> String {
    let absValue = abs(value)
    if absValue >= 1_000_000_000 {
      return String(format: "%.1fB%@", value / 1_000_000_000, suffix)
    }
    if absValue >= 1_000_000 {
      return String(format: "%.1fM%@", value / 1_000_000, suffix)
    }
    if absValue >= 1_000 {
      return String(format: "%.1fK%@", value / 1_000, suffix)
    }
    return numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f%@", value, suffix)
  }

  private static let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter
  }()

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .medium
    return formatter
  }()
}
