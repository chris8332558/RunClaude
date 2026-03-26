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

// MARK: - Engine State

/// Published state from the token usage engine, consumed by the UI layer.
struct UsageState: Sendable {
    var tokensPerSecond: Double = 0.0
    var todayUsage: DailyUsage = DailyUsage(date: Date())
    var recentSamples: [TokenSample] = []
    var isActive: Bool = false
    var weeklyHistory: [HistoryDataPoint] = []   // last 7 days
    var monthlyHistory: [HistoryDataPoint] = []  // last 30 days
}
