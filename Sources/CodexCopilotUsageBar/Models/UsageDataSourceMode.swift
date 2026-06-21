import Foundation

enum UsageDataSourceMode: String, CaseIterable, Identifiable {
  case automatic
  case manual

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic:
      return "Auto Detect"
    case .manual:
      return "Selected Path"
    }
  }
}
