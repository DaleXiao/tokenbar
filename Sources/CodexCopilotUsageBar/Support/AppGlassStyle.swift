import SwiftUI

struct AppGlassStyle {
  let panelTint: Color
  let tileTint: Color
  let border: Color
  let shadow: Color
  let modelIconColor: Color

  static func current(mode: AppAppearanceMode, colorScheme: ColorScheme) -> AppGlassStyle {
    switch mode {
    case .day:
      return AppGlassStyle(
        panelTint: Color(red: 1.0, green: 1.0, blue: 0.985).opacity(0.32),
        tileTint: .white.opacity(0.13),
        border: .white.opacity(0.38),
        shadow: .black.opacity(0.08),
        modelIconColor: .black
      )
    case .night:
      return AppGlassStyle(
        panelTint: Color(red: 0.02, green: 0.023, blue: 0.03).opacity(0.36),
        tileTint: .white.opacity(0.055),
        border: .white.opacity(0.13),
        shadow: .black.opacity(0.22),
        modelIconColor: .white
      )
    case .system:
      return colorScheme == .dark
        ? AppGlassStyle(
          panelTint: .black.opacity(0.20),
          tileTint: .white.opacity(0.05),
          border: .white.opacity(0.14),
          shadow: .black.opacity(0.20),
          modelIconColor: .white
        )
        : AppGlassStyle(
          panelTint: .white.opacity(0.26),
          tileTint: .white.opacity(0.11),
          border: .white.opacity(0.34),
          shadow: .black.opacity(0.07),
          modelIconColor: .black
        )
    }
  }
}
