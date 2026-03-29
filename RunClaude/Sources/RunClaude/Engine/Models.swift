import Foundation

// MARK: - Token Record

/// A single token usage record extracted from a JSONL log line.
struct TokenRecord: Hashable, Sendable {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Deduplication key derived from the raw JSON line.
    let deduplicationKey: String

    /// The JSONL file path this record came from (one file = one Claude Code session).
    let sourceFile: String
}

// MARK: - Daily Usage

/// Aggregated token usage for a single day.
struct DailyUsage: Sendable {
    let date: Date
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var totalTokens: Int = 0
    var estimatedCost: Double = 0.0
    var modelBreakdown: [String: ModelUsage] = [:]
}

/// Token usage attributed to a specific model.
struct ModelUsage: Sendable {
    let model: String
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var totalTokens: Int = 0
    var estimatedCost: Double = 0.0
}

// MARK: - Token Velocity

/// A timestamped token count used for sliding-window velocity calculation.
struct TokenSample: Sendable {
    let timestamp: Date
    let tokens: Int
}

// MARK: - Historical Data Point

/// A single data point in a historical usage chart.
struct HistoryDataPoint: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let totalTokens: Int
    let estimatedCost: Double
    let label: String  // e.g. "Mon", "Mar 15", "Week 12"
}

// MARK: - Live Session Info

/// Live session metrics for a single Claude Code session (one JSONL file).
/// Inspired by `ccusage blocks --live`.
struct SessionInfo: Identifiable, Sendable {
    /// Unique identifier — the JSONL file path.
    var id: String { sourceFile }
    /// The JSONL file path this session corresponds to.
    var sourceFile: String = ""
    /// Short display label derived from the project directory name.
    var displayName: String = ""
    /// Whether this session has had token activity in the last 30 seconds.
    var isActive: Bool = false
    /// Timestamp of the first token record in this session.
    var sessionStart: Date?
    /// Timestamp of the most recent token record in this session.
    var lastActivity: Date?
    /// Seconds elapsed since session start.
    var elapsedSeconds: TimeInterval = 0
    /// Total tokens consumed in this session.
    var totalTokens: Int = 0
    /// Estimated cost for this session.
    var estimatedCost: Double = 0
    /// Average burn rate in tokens per minute over the session.
    var burnRatePerMinute: Double = 0
    /// Burn rate status classification.
    var burnStatus: BurnStatus = .idle
    /// Projected total tokens if current burn rate continues for 8 hours from session start.
    var projectedTokens: Int = 0
    /// Projected cost at current burn rate over 8h session.
    var projectedCost: Double = 0
    /// Projection status classification.
    var projectionStatus: ProjectionStatus = .onTrack
    /// List of model short names active this session.
    var activeModels: [String] = []

    enum BurnStatus: String, Sendable {
        case idle = "IDLE"
        case low = "LOW"
        case normal = "NORMAL"
        case high = "HIGH"
        case extreme = "EXTREME"
    }

    enum ProjectionStatus: String, Sendable {
        case onTrack = "ON TRACK"
        case elevated = "ELEVATED"
        case high = "HIGH"
    }
}

// MARK: - Claude Profile (from ~/.claude.json)

/// Account information from the oauthAccount section of ~/.claude.json.
struct ClaudeAccount: Sendable {
    var displayName: String = ""
    var emailAddress: String = ""
    var organizationName: String = ""
    var organizationRole: String = ""
    var billingType: String = ""
    var hasExtraUsageEnabled: Bool = false

    /// Human-readable billing type label.
    var billingLabel: String {
        switch billingType {
        case "stripe_subscription": return "Pro"
        case "api":                 return "API"
        case "enterprise":          return "Enterprise"
        default:                    return billingType.isEmpty ? "Unknown" : billingType
        }
    }
}

/// A single tool's cumulative usage stats from ~/.claude.json toolUsage.
struct ToolUsageStat: Identifiable, Sendable {
    var id: String { toolName }
    var toolName: String
    var usageCount: Int
    var lastUsedAt: Date?
}

/// An installed Claude Code plugin discovered in ~/.claude/plugins/.
struct PluginInfo: Identifiable, Sendable {
    var id: String { name + (path ?? "") }
    var name: String
    var version: String?
    var description: String?
    var enabled: Bool = true
    var path: String?
}

/// Aggregated profile data from config files + plugin directory.
struct ClaudeProfile: Sendable {
    var account: ClaudeAccount?
    var toolUsage: [ToolUsageStat] = []
    var installedPlugins: [PluginInfo] = []
    var firstStartTime: Date?

    /// Days since first Claude Code session.
    var daysSinceFirstUse: Int? {
        guard let first = firstStartTime else { return nil }
        return Calendar.current.dateComponents([.day], from: first, to: Date()).day
    }

    /// Total tool invocations across all tools.
    var totalToolInvocations: Int {
        toolUsage.reduce(0) { $0 + $1.usageCount }
    }
}

// MARK: - Engine State

/// A single 5-minute bucket for the activity sparkline.
struct SparklineBucket: Sendable {
    let date: Date
    let tokens: Int
}

/// Published state from the token usage engine, consumed by the UI layer.
struct UsageState: Sendable {
    var tokensPerSecond: Double = 0.0
    var todayUsage: DailyUsage = DailyUsage(date: Date())
    var recentSamples: [TokenSample] = []
    var sparklineBuckets: [SparklineBucket] = []  // 5-minute buckets for last 6h
    var liveSessions: [SessionInfo] = []          // per-file live sessions (active first)
    var isActive: Bool = false
    var weeklyHistory: [HistoryDataPoint] = []   // last 7 days
    var monthlyHistory: [HistoryDataPoint] = []  // last 30 days
    var claudeProfile: ClaudeProfile = ClaudeProfile()  // account + tools + plugins
}
