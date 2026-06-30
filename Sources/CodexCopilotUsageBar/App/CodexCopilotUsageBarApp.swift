import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  let store = UsageLogStore()

  private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var popover: NSPopover?
  private var cancellables = Set<AnyCancellable>()
  private var popoverClosedTime: TimeInterval = 0
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var statusIconTrackingArea: NSTrackingArea?
  private var statusIconAnimationTimer: Timer?
  private let showMenuBarUsageNumberKey = "showMenuBarUsageNumber"
  private let statusIconAnimationDuration: TimeInterval = 0.64

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    UserDefaults.standard.register(defaults: [showMenuBarUsageNumberKey: true])
    configureStatusItem()
    configurePopover()
    applyAppearance()
    observeStore()
    observePreferences()
    observeStatusItemClicks()
    observeAppRequests()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
    }
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
    }
    if let statusIconAnimationTimer {
      statusIconAnimationTimer.invalidate()
    }
    if let statusIconTrackingArea, let button = statusItem.button {
      button.removeTrackingArea(statusIconTrackingArea)
    }
  }

  private func configureStatusItem() {
    statusItem.autosaveName = "TokenBar"
    statusItem.isVisible = true

    statusItem.button?.image = MenuBarStatusIcon.image()
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.setAccessibilityLabel("TokenBar")
    installStatusIconHoverTracking()
    updateStatusItemTitle()
  }

  private func configurePopover() {
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.delegate = self

    let hostingController = NSHostingController(rootView: MenuBarDashboardView(store: store))
    hostingController.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hostingController

    self.popover = popover
  }

  private func observeStore() {
    store.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.updateStatusItemTitle()
        }
      }
      .store(in: &cancellables)
  }

  private func observePreferences() {
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.applyAppearance()
        self?.updateStatusItemTitle()
      }
      .store(in: &cancellables)
  }

  private func observeStatusItemClicks() {
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      guard let self, self.shouldOpenPanel(for: event) else {
        return event
      }

      self.openPanel()
      return nil
    }

    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
      guard let self, self.popover?.isShown == true else { return }
      self.closePopover()
    }
  }

  private func installStatusIconHoverTracking() {
    guard let button = statusItem.button else { return }
    if let statusIconTrackingArea {
      button.removeTrackingArea(statusIconTrackingArea)
    }

    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    button.addTrackingArea(trackingArea)
    statusIconTrackingArea = trackingArea
  }

  @objc(mouseEntered:)
  private func statusIconMouseEntered(_ event: NSEvent) {
    runStatusIconHoverAnimation()
  }

  private func runStatusIconHoverAnimation() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

    statusIconAnimationTimer?.invalidate()
    let startTime = Date.timeIntervalSinceReferenceDate
    statusItem.button?.image = MenuBarStatusIcon.image(waveProgress: 0)

    let timer = Timer(timeInterval: 1.0 / 45.0, repeats: true) { [weak self] timer in
      Task { @MainActor [weak self] in
        guard let self else {
          timer.invalidate()
          return
        }

        let elapsed = Date.timeIntervalSinceReferenceDate - startTime
        let progress = min(elapsed / self.statusIconAnimationDuration, 1)
        self.statusItem.button?.image = MenuBarStatusIcon.image(waveProgress: progress)

        if progress >= 1 {
          timer.invalidate()
          self.statusIconAnimationTimer = nil
          self.statusItem.button?.image = MenuBarStatusIcon.image()
        }
      }
    }
    statusIconAnimationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func observeAppRequests() {
    NotificationCenter.default.publisher(for: .tokenBarShowAbout)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.showAboutPanel()
      }
      .store(in: &cancellables)
  }

  private func shouldOpenPanel(for event: NSEvent) -> Bool {
    guard event.window == statusItem.button?.window else {
      return false
    }
    guard !event.modifierFlags.contains(.command) else {
      return false
    }
    guard abs(Date.timeIntervalSinceReferenceDate - popoverClosedTime) > 0.1 else {
      return false
    }
    if popover?.isShown == true {
      closePopover()
      return false
    }
    return true
  }

  private func openPanel() {
    guard let button = statusItem.button, let popover else { return }

    applyAppearance()
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    applyAppearance()
    NSApp.activate(ignoringOtherApps: true)
    popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    button.highlight(true)
  }

  private func closePopover() {
    popover?.close()
    popoverClosedTime = Date.timeIntervalSinceReferenceDate
    statusItem.button?.highlight(false)
  }

  private func updateStatusItemTitle() {
    let shouldShowNumber = UserDefaults.standard.bool(forKey: showMenuBarUsageNumberKey)
    let title = shouldShowNumber ? store.menuBarTitle : ""
    statusItem.button?.title = title.isEmpty ? "" : " \(title)"
    statusItem.button?.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
  }

  private func applyAppearance() {
    let appearance = appearanceMode.nsAppearance
    NSApp.appearance = appearance
    popover?.contentViewController?.view.window?.appearance = appearance
  }

  private var appearanceMode: AppAppearanceMode {
    AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system
  }

  private func showAboutPanel() {
    closePopover()

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      var options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: AppInfo.name,
        .applicationVersion: AppInfo.shortVersion
      ]
      options[.applicationIcon] = NSApplication.shared.applicationIconImage
      NSApp.orderFrontStandardAboutPanel(options: options)
    }
  }

  func popoverWillClose(_ notification: Notification) {
    popoverClosedTime = Date.timeIntervalSinceReferenceDate
    statusItem.button?.highlight(false)
  }
}

private enum MenuBarStatusIcon {
  private static let size = NSSize(width: 18, height: 18)
  private static let baseHeights: [CGFloat] = [5.5, 8.5, 12.5, 7, 10.5]

  static func image(waveProgress: TimeInterval? = nil) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    defer {
      image.unlockFocus()
      image.isTemplate = true
      image.accessibilityDescription = "TokenBar"
    }

    NSColor.black.setFill()

    let barWidth: CGFloat = 2.15
    let spacing: CGFloat = 0.85
    let totalBarWidth = CGFloat(baseHeights.count) * barWidth + CGFloat(baseHeights.count - 1) * spacing
    let startX = (size.width - totalBarWidth) / 2

    let baseline = NSRect(x: startX, y: 2.2, width: totalBarWidth, height: 1.8)
    NSBezierPath(roundedRect: baseline, xRadius: 0.9, yRadius: 0.9).fill()

    for index in baseHeights.indices {
      let height = baseHeights[index] + waveLift(for: index, progress: waveProgress)
      let rect = NSRect(
        x: startX + CGFloat(index) * (barWidth + spacing),
        y: 3.5,
        width: barWidth,
        height: height
      )
      NSBezierPath(roundedRect: rect, xRadius: 1.05, yRadius: 1.05).fill()
    }

    return image
  }

  private static func waveLift(for index: Int, progress: TimeInterval?) -> CGFloat {
    guard let progress else { return 0 }
    let phase = progress * TimeInterval(baseHeights.count) - TimeInterval(index)
    guard (0...1).contains(phase) else { return 0 }
    return CGFloat(sin(phase * .pi)) * 3.8
  }
}

@main
struct CodexCopilotUsageBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue

  var body: some Scene {
    Settings {
      SettingsView(store: appDelegate.store)
        .preferredColorScheme(appearanceMode.colorScheme)
    }
  }

  private var appearanceMode: AppAppearanceMode {
    AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system
  }
}
