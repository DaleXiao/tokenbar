import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    let hostingController = NSHostingController(rootView: MenuBarDashboardView(store: store))
    hostingController.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hostingController
    popover.delegate = self

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
      guard let self, let popover = self.popover, popover.isShown else { return }
      popover.close()
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
    if let popover, popover.isShown {
      popover.close()
      return false
    }
    return true
  }

  private func openPanel() {
    guard let button = statusItem.button, let popover else { return }

    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    NSApp.activate(ignoringOtherApps: true)
    popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    button.highlight(true)
  }

  private func updateStatusItemTitle() {
    let shouldShowNumber = UserDefaults.standard.bool(forKey: showMenuBarUsageNumberKey)
    let title = shouldShowNumber ? store.menuBarTitle : ""
    statusItem.button?.title = title.isEmpty ? "" : " \(title)"
    statusItem.button?.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
  }

  private func showAboutPanel() {
    popover?.close()
    statusItem.button?.highlight(false)

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      var options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: AppInfo.name,
        .applicationVersion: AppInfo.version
      ]
      options[.applicationIcon] = NSApplication.shared.applicationIconImage
      NSApp.orderFrontStandardAboutPanel(options: options)
    }
  }
}

extension AppDelegate: NSPopoverDelegate {
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
