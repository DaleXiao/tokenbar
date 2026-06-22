import AppKit
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

  var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .day: NSAppearance(named: .aqua)
    case .night: NSAppearance(named: .darkAqua)
    }
  }

  static var systemColorScheme: ColorScheme {
    let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    return match == .darkAqua ? .dark : .light
  }

  var toggleSymbolName: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .day: "sun.max.fill"
    case .night: "moon.fill"
    }
  }
}
