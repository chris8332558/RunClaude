import Foundation

// MARK: - Token Aggregator

/// Maintains a sliding window of recent token activity and computes:
/// - tokens/second (drives animation speed)
/// - daily aggregated usage (drives popover stats)
/// - historical daily totals (drives weekly/monthly trend charts)
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

    /// Historical daily usage keyed by day start date.
    /// Populated from all ingested records, used for weekly/monthly charts.
    private var historicalDays: [Date: DailyUsage] = [:]

    /// Timestamp of the first token record seen today (session start proxy).
    private var sessionStartTime: Date?

    /// Assumed session duration for projection (8 hours).
    private let sessionDurationHours: Double = 8.0

    // MARK: - Init

    init(windowDuration: TimeInterval = 10.0) {
        self.windowDuration = windowDuration
        self.dailyUsage = DailyUsage(date: Calendar.current.startOfDay(for: Date()))
    }

    // MARK: - Ingest

    /// Add new token records to the aggregator.
    func ingest(_ records: [TokenRecord]) {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        // Reset daily usage if we've crossed midnight
        if dailyUsage.date != todayStart {
            dailyUsage = DailyUsage(date: todayStart)
            sessionStartTime = nil
        }

        for record in records {
            let tokens = record.totalTokens
            let recordDayStart = calendar.startOfDay(for: record.timestamp)

            // Add to sliding window
            recentSamples.append(TokenSample(timestamp: record.timestamp, tokens: tokens))

            // Track session start (first today record)
            if recordDayStart == todayStart {
                if sessionStartTime == nil || record.timestamp < sessionStartTime! {
                    sessionStartTime = record.timestamp
                }
            }

            // Add to daily aggregation (only count today's records)
            if recordDayStart == todayStart {
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

            // Add to historical daily totals (all days, not just today)
            var dayUsage = historicalDays[recordDayStart] ?? DailyUsage(date: recordDayStart)
            dayUsage.inputTokens += record.inputTokens
            dayUsage.outputTokens += record.outputTokens
            dayUsage.cacheCreationTokens += record.cacheCreationTokens
            dayUsage.cacheReadTokens += record.cacheReadTokens
            dayUsage.totalTokens += tokens

            var modelUsage = dayUsage.modelBreakdown[record.model] ?? ModelUsage(model: record.model)
            modelUsage.inputTokens += record.inputTokens
            modelUsage.outputTokens += record.outputTokens
            modelUsage.cacheCreationTokens += record.cacheCreationTokens
            modelUsage.cacheReadTokens += record.cacheReadTokens
            modelUsage.totalTokens += tokens
            dayUsage.modelBreakdown[record.model] = modelUsage

            historicalDays[recordDayStart] = dayUsage

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

    /// Last 7 days of usage as chart data points.
    var weeklyHistory: [HistoryDataPoint] {
        buildHistory(days: 7)
    }

    /// Last 30 days of usage as chart data points.
    var monthlyHistory: [HistoryDataPoint] {
        buildHistory(days: 30)
    }

    /// Build live session info for the monitor panel.
    func buildSessionInfo() -> SessionInfo {
        let now = Date()
        let todayData = today

        guard let start = sessionStartTime, todayData.totalTokens > 0 else {
            return SessionInfo()
        }

        let elapsed = now.timeIntervalSince(start)
        let elapsedMinutes = max(elapsed / 60.0, 0.1) // avoid division by zero
        let burnRate = Double(todayData.totalTokens) / elapsedMinutes

        // Burn status based on tokens/min
        let burnStatus: SessionInfo.BurnStatus
        switch burnRate {
        case ..<10:     burnStatus = .idle
        case ..<500:    burnStatus = .low
        case ..<5000:   burnStatus = .normal
        case ..<20000:  burnStatus = .high
        default:        burnStatus = .extreme
        }

        // Project total tokens over full session duration
        let sessionMinutes = sessionDurationHours * 60.0
        let projectedTokens = Int(burnRate * sessionMinutes)

        // Project cost: scale today's cost by (sessionMinutes / elapsedMinutes)
        let todayCost = todayData.estimatedCost
        let projectedCost = todayCost * (sessionMinutes / elapsedMinutes)

        // Projection status based on projected daily cost
        let projectionStatus: SessionInfo.ProjectionStatus
        switch projectedCost {
        case ..<10:   projectionStatus = .onTrack
        case ..<50:   projectionStatus = .elevated
        default:      projectionStatus = .high
        }

        // Active models
        let models = todayData.modelBreakdown.keys
            .sorted()
            .map { shortModelName($0) }

        return SessionInfo(
            sessionStart: start,
            elapsedSeconds: elapsed,
            burnRatePerMinute: burnRate,
            burnStatus: burnStatus,
            projectedTokens: projectedTokens,
            projectedCost: projectedCost,
            projectionStatus: projectionStatus,
            activeModels: models
        )
    }

    /// Short model name for session display.
    private func shortModelName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "opus-4" }
        if lower.contains("sonnet") { return "sonnet-4" }
        if lower.contains("haiku") { return "haiku-3.5" }
        let parts = model.split(separator: "-")
        if parts.count > 2 { return parts.prefix(3).joined(separator: "-") }
        return model
    }

    /// Build the full usage state snapshot for the UI.
    func buildState() -> UsageState {
        UsageState(
            tokensPerSecond: tokensPerSecond,
            todayUsage: today,
            recentSamples: Array(recentSamples.suffix(100)),
            sparklineBuckets: sparklineData.map { SparklineBucket(date: $0.date, tokens: $0.tokens) },
            sessionInfo: buildSessionInfo(),
            isActive: isActive,
            weeklyHistory: weeklyHistory,
            monthlyHistory: monthlyHistory
        )
    }

    // MARK: - Private

    private func pruneWindow(now: Date) {
        let cutoff = now.addingTimeInterval(-windowDuration)
        recentSamples.removeAll { $0.timestamp < cutoff }
    }

    private func buildHistory(days: Int) -> [HistoryDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = days <= 7 ? "EEE" : "M/d"

        return (0..<days).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            let dayStart = calendar.startOfDay(for: date)
            let usage = historicalDays[dayStart]
            let cost = computeDayCost(usage)

            return HistoryDataPoint(
                date: dayStart,
                totalTokens: usage?.totalTokens ?? 0,
                estimatedCost: cost,
                label: dayFormatter.string(from: dayStart)
            )
        }
    }

    private func computeDayCost(_ usage: DailyUsage?) -> Double {
        guard let usage = usage else { return 0.0 }
        return usage.modelBreakdown.values.reduce(0.0) { $0 + CostCalculator.cost(for: $1) }
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
