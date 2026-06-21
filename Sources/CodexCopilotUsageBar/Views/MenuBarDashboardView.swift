import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
  @ObservedObject var store: UsageLogStore
  @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue
  @AppStorage("skipQuitConfirmation") private var skipQuitConfirmation = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isSettingsPresented = false
  @State private var isQuitConfirmationPresented = false
  @State private var skipQuitConfirmationDraft = false
  @State private var isLatestExpanded = false
  @State private var isModelsExpanded = false
  @State private var statIconAnimationCycle = 0
  @State private var refreshIconRotation = 0.0
  @State private var settingsIconRotation = 0.0

  private let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8)
  ]

  var body: some View {
    dashboardPanel
      .padding(14)
      .frame(width: 392)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.ultraThinMaterial)
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(glassStyle.panelTint)
      }
      .overlay {
        if isQuitConfirmationPresented {
          quitConfirmationOverlay
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
      }
    .frame(width: 392)
    .environment(\.colorScheme, effectiveColorScheme)
    .preferredColorScheme(appearanceMode.colorScheme)
    .onAppear {
      statIconAnimationCycle += 1
    }
    .onDisappear {
      isSettingsPresented = false
      isQuitConfirmationPresented = false
    }
  }

  private var dashboardPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      LazyVGrid(columns: columns, spacing: 8) {
        StatTile(icon: .today, title: "Today", value: store.summary.today.totalTokens, formatter: UsageFormat.tokens, footnote: messagesText(store.summary.today.requests), glassStyle: glassStyle, animationCycle: statIconAnimationCycle, animationDelay: 0.00)
        StatTile(icon: .allTime, title: "All time", value: store.summary.all.totalTokens, formatter: UsageFormat.tokens, footnote: messagesText(store.summary.all.requests), glassStyle: glassStyle, animationCycle: statIconAnimationCycle, animationDelay: 0.04)
        StatTile(icon: .input, title: "Input", value: store.summary.today.inputTokens, formatter: UsageFormat.tokens, footnote: nil, glassStyle: glassStyle, animationCycle: statIconAnimationCycle, animationDelay: 0.08)
        StatTile(icon: .cacheRead, title: "Cache Read", value: store.summary.today.cachedTokens, formatter: UsageFormat.tokens, footnote: nil, glassStyle: glassStyle, animationCycle: statIconAnimationCycle, animationDelay: 0.12)
        StatTile(icon: .output, title: "Output", value: store.summary.today.outputTokens, formatter: UsageFormat.tokens, footnote: nil, glassStyle: glassStyle, animationCycle: statIconAnimationCycle, animationDelay: 0.16)
        StatTile(icon: .aiu, title: "AIU", value: store.summary.today.nanoAIU, formatter: { UsageFormat.aiu(fromNano: $0) }, footnote: nil, glassStyle: glassStyle, animationCycle: statIconAnimationCycle, animationDelay: 0.20)
      }

      if store.summary.all.requests == 0 {
        EmptyStateView(fileExists: store.fileExists)
      } else {
        modelSection
        detailsSection
      }

      footer
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 3) {
        Text("TokenBar")
          .font(.headline)
        Text(statusLine)
          .font(.caption)
          .foregroundStyle(store.fileExists ? Color.secondary : Color.orange)
      }
      Spacer()
      Button {
        requestQuit()
      } label: {
        Image(systemName: "power")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Quit")
    }
  }

  private var quitConfirmationOverlay: some View {
    ZStack {
      Rectangle()
        .fill(effectiveColorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.22))
        .contentShape(Rectangle())
        .onTapGesture {
          dismissQuitConfirmation()
        }

      QuitConfirmationDialog(
        isDoNotAskAgainSelected: $skipQuitConfirmationDraft,
        glassStyle: glassStyle,
        onCancel: dismissQuitConfirmation,
        onQuit: confirmQuit
      )
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .onTapGesture {}
    }
  }

  private var detailsSection: some View {
    CollapsibleSection("Details", isExpanded: $isLatestExpanded) {
      VStack(alignment: .leading, spacing: 7) {
        ForEach(Array(store.summary.recent.enumerated()), id: \.offset) { _, record in
          LatestRecordRow(record: record)
        }
      }
      .padding(.top, 4)
    }
  }

  private var modelSection: some View {
    CollapsibleSection("Models", isExpanded: $isModelsExpanded) {
      VStack(alignment: .leading, spacing: 7) {
        ForEach(store.summary.byModel.prefix(4)) { row in
          ModelUsageRow(row: row, iconColor: glassStyle.modelIconColor)
        }
      }
      .padding(.top, 4)
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      Spacer()

      Button {
        spinRefreshIcon()
        store.refreshNow()
        statIconAnimationCycle += 1
      } label: {
        Image(systemName: "arrow.triangle.2.circlepath")
          .rotationEffect(.degrees(refreshIconRotation))
      }
      .help("Refresh")

      Button {
        spinSettingsIcon()
        isSettingsPresented.toggle()
      } label: {
        Image(systemName: "gearshape")
          .rotationEffect(.degrees(settingsIconRotation))
      }
      .help("Settings")
      .background {
        SettingsMenuPresenter(
          isPresented: $isSettingsPresented,
          store: store
        )
        .frame(width: 24, height: 24)
        .allowsHitTesting(false)
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
  }

  private var statusLine: String {
    if let lastRefreshDate = store.lastRefreshDate {
      return "Updated at: \(UsageFormat.time(lastRefreshDate))"
    }
    return store.statusText
  }

  private func messagesText(_ count: Int) -> String {
    "\(UsageFormat.integer(count)) Messages"
  }

  private var appearanceMode: AppAppearanceMode {
    AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system
  }

  private var effectiveColorScheme: ColorScheme {
    appearanceMode.colorScheme ?? colorScheme
  }

  private var glassStyle: AppGlassStyle {
    AppGlassStyle.current(mode: appearanceMode, colorScheme: effectiveColorScheme)
  }

  private func spinRefreshIcon() {
    guard !reduceMotion else { return }
    withAnimation(.easeInOut(duration: 0.34)) {
      refreshIconRotation += 180
    }
  }

  private func spinSettingsIcon() {
    guard !reduceMotion else { return }
    withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
      settingsIconRotation += 90
    }
  }

  private func requestQuit() {
    if skipQuitConfirmation {
      NSApplication.shared.terminate(nil)
      return
    }

    isSettingsPresented = false
    skipQuitConfirmationDraft = false
    withAnimation(.easeOut(duration: 0.16)) {
      isQuitConfirmationPresented = true
    }
  }

  private func dismissQuitConfirmation() {
    skipQuitConfirmationDraft = false
    withAnimation(.easeOut(duration: 0.16)) {
      isQuitConfirmationPresented = false
    }
  }

  private func confirmQuit() {
    skipQuitConfirmation = skipQuitConfirmationDraft
    NSApplication.shared.terminate(nil)
  }
}

private struct QuitConfirmationDialog: View {
  @Binding var isDoNotAskAgainSelected: Bool
  let glassStyle: AppGlassStyle
  let onCancel: () -> Void
  let onQuit: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)

      VStack(spacing: 5) {
        Text("Quit TokenBar?")
          .font(.headline)
        Text("TokenBar will stop updating usage until you open it again.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button {
        isDoNotAskAgainSelected.toggle()
      } label: {
        HStack(spacing: 8) {
          ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(isDoNotAskAgainSelected ? Color.accentColor : Color.clear)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .strokeBorder(isDoNotAskAgainSelected ? Color.accentColor : Color.primary.opacity(0.55), lineWidth: 1.3)

            if isDoNotAskAgainSelected {
              Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          .frame(width: 16, height: 16)

          Text("Don't ask again")
            .font(.caption)
            .foregroundStyle(.primary)

          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      HStack(spacing: 8) {
        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)

        Button("Quit", role: .destructive) {
          onQuit()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(16)
    .frame(width: 300)
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.ultraThinMaterial)
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(glassStyle.panelTint)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(glassStyle.border)
    }
    .shadow(color: glassStyle.shadow, radius: 18, x: 0, y: 10)
  }
}

private struct SettingsMenuPresenter: NSViewRepresentable {
  @Binding var isPresented: Bool
  let store: UsageLogStore

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.isPresented = $isPresented
    context.coordinator.store = store

    if isPresented {
      DispatchQueue.main.async {
        context.coordinator.showMenu(from: nsView)
      }
    }
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.closeMenu()
  }

  @MainActor
  final class Coordinator: NSObject, NSMenuDelegate {
    var isPresented: Binding<Bool>?
    weak var store: UsageLogStore?

    private let appearanceModeKey = "appearanceMode"
    private let showMenuBarUsageNumberKey = "showMenuBarUsageNumber"
    private var menu: NSMenu?
    private var isMenuOpen = false

    func showMenu(from view: NSView) {
      guard let store, view.window != nil else { return }
      guard !isMenuOpen else { return }

      let menu = makeMenu(store: store)
      menu.delegate = self
      self.menu = menu
      isMenuOpen = true
      menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.maxY + 2), in: view)
    }

    func closeMenu() {
      menu?.cancelTracking()
      menu = nil
      isMenuOpen = false
    }

    func menuDidClose(_ menu: NSMenu) {
      isPresented?.wrappedValue = false
      isMenuOpen = false
      self.menu = nil
    }

    private func makeMenu(store: UsageLogStore) -> NSMenu {
      let menu = NSMenu(title: "Settings")
      menu.autoenablesItems = false

      let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
      let appearanceMenu = NSMenu(title: "Appearance")
      let currentMode = AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: appearanceModeKey) ?? "") ?? .system
      for mode in [AppAppearanceMode.day, .night, .system] {
        let item = NSMenuItem(title: mode.title, action: #selector(setAppearanceMode(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        item.state = currentMode == mode ? .on : .off
        appearanceMenu.addItem(item)
      }
      menu.setSubmenu(appearanceMenu, for: appearanceItem)
      menu.addItem(appearanceItem)

      let launchItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
      launchItem.target = self
      launchItem.state = LaunchAtLoginService.isEnabled ? .on : .off
      menu.addItem(launchItem)

      let logItem = NSMenuItem(title: "Log", action: nil, keyEquivalent: "")
      let logMenu = NSMenu(title: "Log")
      let pathItem = NSMenuItem(title: store.logPath, action: nil, keyEquivalent: "")
      pathItem.isEnabled = false
      pathItem.toolTip = store.logPath
      logMenu.addItem(pathItem)
      let choosePathItem = NSMenuItem(title: "Choose Log File...", action: #selector(chooseLogFile(_:)), keyEquivalent: "")
      choosePathItem.target = self
      logMenu.addItem(choosePathItem)
      menu.setSubmenu(logMenu, for: logItem)
      menu.addItem(logItem)

      let showUsageItem = NSMenuItem(title: "Show Usage Number", action: #selector(toggleUsageNumber(_:)), keyEquivalent: "")
      showUsageItem.target = self
      showUsageItem.state = UserDefaults.standard.bool(forKey: showMenuBarUsageNumberKey) ? .on : .off
      menu.addItem(showUsageItem)

      menu.addItem(.separator())
      let aboutItem = NSMenuItem(title: "About TokenBar", action: #selector(showAbout(_:)), keyEquivalent: "")
      aboutItem.target = self
      menu.addItem(aboutItem)
      return menu
    }

    @objc private func setAppearanceMode(_ item: NSMenuItem) {
      guard let rawValue = item.representedObject as? String else { return }
      UserDefaults.standard.set(rawValue, forKey: appearanceModeKey)
    }

    @objc private func toggleOpenAtLogin(_ item: NSMenuItem) {
      do {
        try LaunchAtLoginService.setEnabled(!LaunchAtLoginService.isEnabled)
      } catch {
        showErrorAlert(message: error.localizedDescription)
      }
    }

    @objc private func chooseLogFile(_ item: NSMenuItem) {
      guard let store else { return }
      DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.title = "Choose Usage Log"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.logFileURL.deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
          store.setLogFileURL(url)
        }
      }
    }

    @objc private func toggleUsageNumber(_ item: NSMenuItem) {
      let isEnabled = UserDefaults.standard.bool(forKey: showMenuBarUsageNumberKey)
      UserDefaults.standard.set(!isEnabled, forKey: showMenuBarUsageNumberKey)
    }

    @objc private func showAbout(_ item: NSMenuItem) {
      NotificationCenter.default.post(name: .tokenBarShowAbout, object: nil)
    }

    private func showErrorAlert(message: String) {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "TokenBar"
      alert.informativeText = message
      alert.runModal()
    }
  }
}

private struct CollapsibleSection<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content

  init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    _isExpanded = isExpanded
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 10)
          Text(title)
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        content()
      }
    }
  }
}

private struct StatTile: View {
  let icon: StatSVGIcon
  let title: String
  let value: Double
  let formatter: (Double) -> String
  let footnote: String?
  let glassStyle: AppGlassStyle
  let animationCycle: Int
  let animationDelay: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isIconVisible = false
  @State private var animatedValue = 0.0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .center, spacing: 6) {
        StatSVGIconView(icon: icon)
          .opacity(isIconVisible ? 1 : 0)
          .scaleEffect(reduceMotion ? 1 : (isIconVisible ? 1 : 0.84))
          .offset(y: reduceMotion ? 0 : (isIconVisible ? 0 : 3))
          .blur(radius: reduceMotion ? 0 : (isIconVisible ? 0 : 1.2))
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      AnimatedMetricText(value: animatedValue, formatter: formatter)
        .font(.title3.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      if let footnote {
        Text(footnote)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(glassStyle.tileTint)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(glassStyle.border)
    }
    .onAppear {
      runEntryAnimation()
    }
    .onChange(of: animationCycle) { _, _ in
      runEntryAnimation()
    }
    .onChange(of: value) { _, newValue in
      withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.35)) {
        animatedValue = newValue
      }
    }
  }

  private func runEntryAnimation() {
    isIconVisible = false
    animatedValue = 0
    DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
      withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .interpolatingSpring(stiffness: 210, damping: 16)) {
        isIconVisible = true
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay + 0.16) {
      withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.72)) {
        animatedValue = value
      }
    }
  }
}

private struct AnimatedMetricText: View {
  let value: Double
  let formatter: (Double) -> String

  var body: some View {
    Text("")
      .modifier(AnimatedMetricTextModifier(value: value, formatter: formatter))
  }
}

private struct AnimatedMetricTextModifier: AnimatableModifier {
  var value: Double
  let formatter: (Double) -> String

  var animatableData: Double {
    get { value }
    set { value = newValue }
  }

  func body(content: Content) -> some View {
    Text(formatter(value))
  }
}

private struct LatestRecordRow: View {
  let record: UsageRecord

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(record.model ?? "unknown")
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .truncationMode(.middle)
        Text("\(record.surface ?? "-") · \(record.mode ?? "-") · \(UsageFormat.time(record.date))")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Text(UsageFormat.tokens(record.usage?.totalTokens ?? 0))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }
}

private struct ModelUsageRow: View {
  let row: ModelUsage
  let iconColor: Color

  var body: some View {
    HStack(spacing: 8) {
      ModelProviderSVGIconView(model: row.model, color: iconColor)
      Text(row.model)
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text("\(UsageFormat.tokens(row.totals.totalTokens)) · \(UsageFormat.integer(row.totals.requests))")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

private struct EmptyStateView: View {
  let fileExists: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(fileExists ? "No usage records" : "Log not found")
        .font(.subheadline.weight(.semibold))
      Text(fileExists ? "Waiting for upstream usage metadata." : "The default usage file has not been created yet.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
