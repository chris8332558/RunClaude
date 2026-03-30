import Foundation

// MARK: - Claude Config Reader

/// Reads metadata from `~/.claude.json` and `~/.claude/plugins/` to enrich
/// the RunClaude UI with account info, tool usage stats, and installed plugins.
final class ClaudeConfigReader {

    /// Cached profile to avoid re-reading files every 0.5s.
    private var cachedProfile: ClaudeProfile?
    private var lastReadTime: Date?
    private let cacheInterval: TimeInterval = 30.0  // re-read every 30s

    // MARK: - Public

    /// Read the full Claude profile (account + tools + plugins).
    /// Caches for `cacheInterval` seconds to avoid excessive disk I/O.
    func readProfile() -> ClaudeProfile {
        let now = Date()
        if let cached = cachedProfile, let lastRead = lastReadTime,
           now.timeIntervalSince(lastRead) < cacheInterval {
            return cached
        }

        let profile = ClaudeProfile(
            account: readAccount(),
            toolUsage: readToolUsage(),
            installedPlugins: readPlugins(),
            installedSkills: readSkills(),
            firstStartTime: readFirstStartTime()
        )

        cachedProfile = profile
        lastReadTime = now
        return profile
    }

    /// Force a re-read on next call (e.g. after user changes settings).
    func invalidateCache() {
        cachedProfile = nil
        lastReadTime = nil
    }

    // MARK: - ~/.claude.json Parsing

    /// Path to the main Claude config file.
    private var claudeJsonPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude.json"
    }

    /// Read the raw JSON dictionary from ~/.claude.json.
    private func readClaudeJson() -> [String: Any]? {
        let path = claudeJsonPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    /// Extract OAuth account info.
    private func readAccount() -> ClaudeAccount? {
        guard let json = readClaudeJson(),
              let oauth = json["oauthAccount"] as? [String: Any]
        else { return nil }

        return ClaudeAccount(
            displayName: oauth["displayName"] as? String ?? "",
            emailAddress: oauth["emailAddress"] as? String ?? "",
            organizationName: oauth["organizationName"] as? String ?? "",
            organizationRole: oauth["organizationRole"] as? String ?? "",
            billingType: oauth["billingType"] as? String ?? "",
            hasExtraUsageEnabled: oauth["hasExtraUsageEnabled"] as? Bool ?? false
        )
    }

    /// Extract tool usage statistics.
    private func readToolUsage() -> [ToolUsageStat] {
        guard let json = readClaudeJson(),
              let toolUsage = json["toolUsage"] as? [String: Any]
        else { return [] }

        return toolUsage.compactMap { key, value -> ToolUsageStat? in
            guard let info = value as? [String: Any],
                  let count = info["usageCount"] as? Int
            else { return nil }

            let lastUsedMs = info["lastUsedAt"] as? Double ?? 0
            let lastUsedDate = lastUsedMs > 0
                ? Date(timeIntervalSince1970: lastUsedMs / 1000.0)
                : nil

            return ToolUsageStat(
                toolName: key,
                usageCount: count,
                lastUsedAt: lastUsedDate
            )
        }
        .sorted { $0.usageCount > $1.usageCount }
    }

    /// Extract firstStartTime.
    private func readFirstStartTime() -> Date? {
        guard let json = readClaudeJson(),
              let dateStr = json["firstStartTime"] as? String
        else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateStr)
    }

    // MARK: - ~/.claude/plugins/ Scanning

    /// Discover installed plugins from the plugins directory.
    private func readPlugins() -> [PluginInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pluginsPath = "\(home)/.claude/plugins"
        let fm = FileManager.default

        guard fm.fileExists(atPath: pluginsPath) else { return [] }

        var plugins: [PluginInfo] = []

        guard let contents = try? fm.contentsOfDirectory(atPath: pluginsPath) else { return [] }

        for item in contents {
            let itemPath = "\(pluginsPath)/\(item)"
            var isDir: ObjCBool = false

            if fm.fileExists(atPath: itemPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Plugin directory — look for manifest/package.json/plugin.json
                    let plugin = parsePluginDirectory(name: item, path: itemPath)
                    plugins.append(plugin)
                } else if item.hasSuffix(".json") {
                    // Could be a plugin manifest file
                    if let plugin = parsePluginFile(path: itemPath) {
                        plugins.append(plugin)
                    }
                }
            }
        }

        return plugins.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Parse a plugin directory for metadata.
    private func parsePluginDirectory(name: String, path: String) -> PluginInfo {
        let fm = FileManager.default

        // Try common manifest files
        let manifestPaths = [
            "\(path)/package.json",
            "\(path)/plugin.json",
            "\(path)/manifest.json",
            "\(path)/config.json"
        ]

        for manifestPath in manifestPaths {
            if fm.fileExists(atPath: manifestPath),
               let data = fm.contents(atPath: manifestPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return PluginInfo(
                    name: json["name"] as? String ?? name,
                    version: json["version"] as? String,
                    description: json["description"] as? String,
                    enabled: json["enabled"] as? Bool ?? true,
                    path: path
                )
            }
        }

        // No manifest found — use directory name
        return PluginInfo(
            name: name,
            version: nil,
            description: nil,
            enabled: true,
            path: path
        )
    }

    // MARK: - ~/.claude/plugins/marketplaces/.../skills/ Scanning

    /// Discover installed skills from marketplace skill directories.
    /// Skills are directories under ~/.claude/plugins/marketplaces/<marketplace>/skills/.
    private func readSkills() -> [SkillInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let marketplacesPath = "\(home)/.claude/plugins/marketplaces"
        let fm = FileManager.default

        guard fm.fileExists(atPath: marketplacesPath) else { return [] }
        guard let marketplaces = try? fm.contentsOfDirectory(atPath: marketplacesPath) else { return [] }

        var skills: [SkillInfo] = []

        for marketplace in marketplaces {
            let skillsDir = "\(marketplacesPath)/\(marketplace)/skills"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: skillsDir, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let skillNames = try? fm.contentsOfDirectory(atPath: skillsDir) else { continue }

            for skillName in skillNames {
                let skillPath = "\(skillsDir)/\(skillName)"
                var skillIsDir: ObjCBool = false
                if fm.fileExists(atPath: skillPath, isDirectory: &skillIsDir), skillIsDir.boolValue {
                    skills.append(SkillInfo(name: skillName, marketplace: marketplace))
                }
            }
        }

        return skills.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Parse a standalone plugin JSON file.
    private func parsePluginFile(path: String) -> PluginInfo? {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String
        else { return nil }

        return PluginInfo(
            name: name,
            version: json["version"] as? String,
            description: json["description"] as? String,
            enabled: json["enabled"] as? Bool ?? true,
            path: path
        )
    }
}
