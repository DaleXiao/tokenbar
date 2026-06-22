import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: UsageLogStore
  let embedded: Bool

  @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue
  @AppStorage("showMenuBarUsageNumber") private var showMenuBarUsageNumber = true
  @State private var launchAtLogin = LaunchAtLoginService.isEnabled
  @State private var launchAtLoginError: String?
  @State private var isDataSourceExpanded = false

  init(store: UsageLogStore, embedded: Bool = false) {
    self.store = store
    self.embedded = embedded
  }

  var body: some View {
    content
    .padding(embedded ? 0 : 20)
    .frame(width: embedded ? nil : 440, height: embedded ? nil : 360)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Appearance")
          .font(.caption)
          .foregroundStyle(.secondary)

        AppearanceModeToggle(selection: $appearanceModeRaw)
      }

      CheckboxToggle(title: "Show Usage Next to Icon", isOn: $showMenuBarUsageNumber)

      CheckboxToggle(title: "Open at Login", isOn: launchAtLoginBinding)

      if let launchAtLoginError {
        Text(launchAtLoginError)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      SettingsCollapsibleSection("Data Source", isExpanded: $isDataSourceExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Mode", selection: dataSourceModeBinding) {
            ForEach(UsageDataSourceMode.allCases) { mode in
              Text(mode.title).tag(mode.rawValue)
            }
          }
          .pickerStyle(.segmented)

          Text(store.dataSourceDescription)
            .font(.caption)
            .foregroundStyle(.secondary)

          Text(store.logPath)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .truncationMode(.middle)
            .textSelection(.enabled)

          Button {
            chooseDataSourcePath()
          } label: {
            Label("Choose Path...", systemImage: "folder.badge.plus")
          }
          .buttonStyle(.bordered)
        }
        .padding(.top, 4)
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text("About")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          AppIconView()
          Text(AppInfo.name)
        }
        LabeledContent("Version", value: AppInfo.version)
      }
    }
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding {
      launchAtLogin
    } set: { newValue in
      do {
        try LaunchAtLoginService.setEnabled(newValue)
        launchAtLogin = newValue
        launchAtLoginError = nil
      } catch {
        launchAtLogin = LaunchAtLoginService.isEnabled
        launchAtLoginError = error.localizedDescription
      }
    }
  }

  private var dataSourceModeBinding: Binding<String> {
    Binding {
      store.dataSourceMode.rawValue
    } set: { rawValue in
      guard let mode = UsageDataSourceMode(rawValue: rawValue) else { return }
      store.setDataSourceMode(mode)
    }
  }

  private func chooseDataSourcePath() {
    let panel = NSOpenPanel()
    panel.title = "Choose Data Source"
    panel.prompt = "Choose"
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = store.logFileURL.deletingLastPathComponent()

    if panel.runModal() == .OK, let url = panel.url {
      store.setLogFileURL(url)
    }
  }
}

private struct SettingsCollapsibleSection<Content: View>: View {
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
            .foregroundStyle(.primary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 10)
          Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
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

private struct AppIconView: View {
  var body: some View {
    Image(nsImage: NSApplication.shared.applicationIconImage)
      .resizable()
      .scaledToFit()
      .frame(width: 22, height: 22)
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      .accessibilityHidden(true)
  }
}

private struct AppearanceModeToggle: View {
  @Binding var selection: String

  private let options: [AppAppearanceMode] = [.night, .day, .system]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(options) { mode in
        Button {
          withAnimation(.interpolatingSpring(stiffness: 260, damping: 22)) {
            selection = mode.rawValue
          }
        } label: {
          Image(systemName: mode.toggleSymbolName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 38, height: 38)
            .foregroundStyle(selection == mode.rawValue ? .white : Color.primary.opacity(0.62))
            .background {
              if selection == mode.rawValue {
                Circle()
                  .fill(Color.accentColor)
                  .shadow(color: Color.accentColor.opacity(0.35), radius: 5, x: 0, y: 2)
              }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .accessibilityLabel(mode.title)
      }
    }
    .padding(5)
    .background {
      Capsule(style: .continuous)
        .fill(Color.black.opacity(0.20))
      Capsule(style: .continuous)
        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
    }
    .frame(height: 48)
  }
}

private struct CheckboxToggle: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isOn ? Color.accentColor : Color.clear)
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(isOn ? Color.accentColor : Color.primary.opacity(0.55), lineWidth: 1.4)

          if isOn {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
          }
        }
        .frame(width: 17, height: 17)

        Text(title)
          .foregroundStyle(.primary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(isOn ? "On" : "Off")
  }
}
