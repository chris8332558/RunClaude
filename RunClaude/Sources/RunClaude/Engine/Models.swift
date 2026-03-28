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

/// Live session metrics inspired by `ccusage blocks --live`.
struct SessionInfo: Sendable {
    /// Timestamp of the first token record seen today.
    var sessionStart: Date?
    /// Seconds elapsed since session start.
    var elapsedSeconds: TimeInterval = 0
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
    var sessionInfo: SessionInfo = SessionInfo()  // live session monitor
    var isActive: Bool = false
    var weeklyHistory: [HistoryDataPoint] = []   // last 7 days
    var monthlyHistory: [HistoryDataPoint] = []  // last 30 days
}
