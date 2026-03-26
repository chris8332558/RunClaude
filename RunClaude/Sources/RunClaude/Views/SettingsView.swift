import SwiftUI

// MARK: - Settings View

/// Preferences window for RunClaude.
/// Will be expanded in Phase 3. Provides basic configuration for now.
struct SettingsView: View {
    @AppStorage("customDataPath") private var customDataPath: String = ""
    @AppStorage("showCostInTooltip") private var showCostInTooltip: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

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
                        // TODO: Phase 3 — use SMAppService to register/unregister
                        print("[RunClaude] Launch at login: \(newValue) (not yet implemented)")
                    }
            }

            Section("About") {
                HStack {
                    Text("RunClaude v0.1.0")
                    Spacer()
                    Link("GitHub", destination: URL(string: "https://github.com/your-username/RunClaude")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
    }
}
