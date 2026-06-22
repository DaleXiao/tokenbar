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
  private let showMenuBarUsageNumberKey = "showMenuBarUsageNumber"

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
  }

  private func configureStatusItem() {
    statusItem.autosaveName = "TokenBar"
    statusItem.isVisible = true

    let image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "TokenBar")
    image?.isTemplate = true

    statusItem.button?.image = image
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.setAccessibilityLabel("TokenBar")
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
