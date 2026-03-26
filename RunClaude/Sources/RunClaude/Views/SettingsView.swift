import SwiftUI
import ServiceManagement

// MARK: - Settings View

/// Preferences window for RunClaude.
struct SettingsView: View {
    @AppStorage("customDataPath") private var customDataPath: String = ""
    @AppStorage("showCostInTooltip") private var showCostInTooltip: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("selectedSpritePack") private var selectedPackId: String = SpritePackRegistry.defaultPackId
    @AppStorage(CostAlertManager.enabledKey) private var costAlertEnabled: Bool = false
    @AppStorage(CostAlertManager.thresholdKey) private var costAlertThreshold: Double = 5.0
    @State private var loginItemError: String?

    /// Callback when sprite pack changes (set by MenuBarController).
    var onSpritePackChanged: ((String) -> Void)?

    var body: some View {
        Form {
            Section("Character") {
                Picker("Sprite Pack", selection: $selectedPackId) {
                    ForEach(SpritePackRegistry.allPacks, id: \.id) { pack in
                        Text(pack.displayName).tag(pack.id)
                    }
                }
                .onChange(of: selectedPackId) { newValue in
                    onSpritePackChanged?(newValue)
                }
            }

            Section("Data Source") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code data directory")
                        .font(.subheadline)

                    let defaultPaths = LogFileWatcher.discoverClaudeDataPaths()
                    if defaultPaths.isEmpty {
                        Text("No Claude Code data directory found at default locations.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        ForEach(defaultPaths, id: \.self) { path in
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    TextField("Custom path (optional)", text: $customDataPath)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Cost Alerts") {
                Toggle("Enable cost alert", isOn: $costAlertEnabled)

                if costAlertEnabled {
                    HStack {
                        Text("Alert when daily cost exceeds")
                            .font(.subheadline)
                        Spacer()
                        TextField("$", value: $costAlertThreshold, format: .currency(code: "USD"))
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                }
            }

            Section("Display") {
                Toggle("Show cost in tooltip", isOn: $showCostInTooltip)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }

                if let error = loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("About") {
                HStack {
                    Text("RunClaude v0.2.0")
                    Spacer()
                    Text("macOS menu bar token monitor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 480)
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginItemError = nil
            } catch {
                loginItemError = "Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                launchAtLogin = !enabled
            }
        }
    }
}
