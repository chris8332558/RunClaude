import SwiftUI
import ServiceManagement

// MARK: - Settings View

/// Preferences window for RunClaude.
struct SettingsView: View {
    @AppStorage("customDataPath") private var customDataPath: String = ""
    @AppStorage("showCostInTooltip") private var showCostInTooltip: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @State private var loginItemError: String?

    var body: some View {
        Form {
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
                    Text("RunClaude v0.1.0")
                    Spacer()
                    Text("macOS menu bar token monitor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 340)
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
                // Revert the toggle
                launchAtLogin = !enabled
            }
        }
    }
}
