import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
  case system
  case day
  case night

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .day: "Day"
    case .night: "Night"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .day: .light
    case .night: .dark
    }
  }

  var toggleSymbolName: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .day: "sun.max.fill"
    case .night: "moon.fill"
    }
  }
}
