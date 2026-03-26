import Foundation

// MARK: - Token Aggregator

/// Maintains a sliding window of recent token activity and computes:
/// - tokens/second (drives animation speed)
/// - daily aggregated usage (drives popover stats)
final class TokenAggregator {

    /// Sliding window duration for velocity calculation.
    private let windowDuration: TimeInterval

    /// Recent token samples within the sliding window.
    private var recentSamples: [TokenSample] = []

    /// Daily usage accumulator (resets at midnight).
    private var dailyUsage: DailyUsage

    /// Per-5-minute buckets for the sparkline chart (last 6 hours = 72 buckets).
    private var minuteBuckets: [Date: Int] = [:]
    private let bucketInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Init

    init(windowDuration: TimeInterval = 10.0) {
        self.windowDuration = windowDuration
        self.dailyUsage = DailyUsage(date: Calendar.current.startOfDay(for: Date()))
    }

    // MARK: - Ingest

    /// Add new token records to the aggregator.
    func ingest(_ records: [TokenRecord]) {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)

        // Reset daily usage if we've crossed midnight
        if dailyUsage.date != todayStart {
            dailyUsage = DailyUsage(date: todayStart)
        }

        for record in records {
            let tokens = record.totalTokens

            // Add to sliding window
            recentSamples.append(TokenSample(timestamp: record.timestamp, tokens: tokens))

            // Add to daily aggregation (only count today's records)
            if Calendar.current.isDateInToday(record.timestamp) {
                dailyUsage.inputTokens += record.inputTokens
                dailyUsage.outputTokens += record.outputTokens
                dailyUsage.cacheCreationTokens += record.cacheCreationTokens
                dailyUsage.cacheReadTokens += record.cacheReadTokens
                dailyUsage.totalTokens += tokens

                // Model breakdown
                var modelUsage = dailyUsage.modelBreakdown[record.model] ?? ModelUsage(model: record.model)
                modelUsage.inputTokens += record.inputTokens
                modelUsage.outputTokens += record.outputTokens
                modelUsage.cacheCreationTokens += record.cacheCreationTokens
                modelUsage.cacheReadTokens += record.cacheReadTokens
                modelUsage.totalTokens += tokens
                dailyUsage.modelBreakdown[record.model] = modelUsage
            }

            // Add to 5-minute buckets
            let bucketDate = record.timestamp.rounded(to: bucketInterval)
            minuteBuckets[bucketDate, default: 0] += tokens
        }

        // Prune old samples from the sliding window
        pruneWindow(now: now)

        // Prune old minute buckets (keep last 6 hours)
        let cutoff = now.addingTimeInterval(-6 * 3600)
        minuteBuckets = minuteBuckets.filter { $0.key >= cutoff }
    }

    // MARK: - Queries

    /// Current tokens per second based on the sliding window.
    var tokensPerSecond: Double {
        let now = Date()
        pruneWindow(now: now)

        guard !recentSamples.isEmpty else { return 0.0 }

        let totalTokens = recentSamples.reduce(0) { $0 + $1.tokens }
        let windowStart = now.addingTimeInterval(-windowDuration)
        let effectiveWindow = now.timeIntervalSince(
            max(windowStart, recentSamples.first?.timestamp ?? windowStart)
        )

        guard effectiveWindow > 0.1 else { return 0.0 }
        return Double(totalTokens) / effectiveWindow
    }

    /// Whether there's been any token activity in the last few seconds.
    var isActive: Bool {
        let now = Date()
        guard let lastSample = recentSamples.last else { return false }
        return now.timeIntervalSince(lastSample.timestamp) < 5.0
    }

    /// Today's aggregated usage.
    var today: DailyUsage {
        let todayStart = Calendar.current.startOfDay(for: Date())
        if dailyUsage.date != todayStart {
            dailyUsage = DailyUsage(date: todayStart)
        }
        return dailyUsage
    }

    /// Recent 5-minute token buckets for sparkline rendering.
    var sparklineData: [(date: Date, tokens: Int)] {
        minuteBuckets
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, tokens: $0.value) }
    }

    /// Build the full usage state snapshot for the UI.
    func buildState() -> UsageState {
        UsageState(
            tokensPerSecond: tokensPerSecond,
            todayUsage: today,
            recentSamples: Array(recentSamples.suffix(100)),
            isActive: isActive
        )
    }

    // MARK: - Private

    private func pruneWindow(now: Date) {
        let cutoff = now.addingTimeInterval(-windowDuration)
        recentSamples.removeAll { $0.timestamp < cutoff }
    }
}

// MARK: - Date Helpers

private extension Date {
    /// Round down to the nearest interval boundary.
    func rounded(to interval: TimeInterval) -> Date {
        let seconds = timeIntervalSince1970
        let rounded = (seconds / interval).rounded(.down) * interval
        return Date(timeIntervalSince1970: rounded)
    }
}
