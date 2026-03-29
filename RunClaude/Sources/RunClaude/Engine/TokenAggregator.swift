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

    /// Per-file (per-session) tracking. Key is the JSONL file path.
    private var fileSessions: [String: FileSession] = [:]

    /// Assumed session duration for projection (8 hours).
    private let sessionDurationHours: Double = 8.0

    /// How long after last activity before a session is considered inactive.
    private let sessionInactiveTimeout: TimeInterval = 30.0

    /// Internal per-file session accumulator.
    struct FileSession {
        var sourceFile: String
        var firstRecord: Date
        var lastRecord: Date
        var totalTokens: Int = 0
        var models: Set<String> = []
        var modelBreakdown: [String: ModelUsage] = [:]
    }

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
            fileSessions.removeAll()
        }

        for record in records {
            let tokens = record.totalTokens
            let recordDayStart = calendar.startOfDay(for: record.timestamp)

            // Add to sliding window
            recentSamples.append(TokenSample(timestamp: record.timestamp, tokens: tokens))

            // Track per-file session data
            if !record.sourceFile.isEmpty {
                var session = fileSessions[record.sourceFile] ?? FileSession(
                    sourceFile: record.sourceFile,
                    firstRecord: record.timestamp,
                    lastRecord: record.timestamp
                )
                if record.timestamp < session.firstRecord {
                    session.firstRecord = record.timestamp
                }
                if record.timestamp > session.lastRecord {
                    session.lastRecord = record.timestamp
                }
                session.totalTokens += tokens
                session.models.insert(record.model)

                var mu = session.modelBreakdown[record.model] ?? ModelUsage(model: record.model)
                mu.inputTokens += record.inputTokens
                mu.outputTokens += record.outputTokens
                mu.cacheCreationTokens += record.cacheCreationTokens
                mu.cacheReadTokens += record.cacheReadTokens
                mu.totalTokens += tokens
                session.modelBreakdown[record.model] = mu

                fileSessions[record.sourceFile] = session
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

    /// Build live session info for all tracked JSONL files.
    /// Returns sessions sorted: active first (by recency), then inactive (by recency).
    func buildLiveSessions() -> [SessionInfo] {
        let now = Date()
        let sessionMinutes = sessionDurationHours * 60.0

        return fileSessions.values
            .filter { $0.totalTokens > 0 }
            .map { session -> SessionInfo in
                let elapsed = now.timeIntervalSince(session.firstRecord)
                let elapsedMinutes = max(elapsed / 60.0, 0.1)
                let burnRate = Double(session.totalTokens) / elapsedMinutes
                let active = now.timeIntervalSince(session.lastRecord) < sessionInactiveTimeout

                // Burn status
                let burnStatus: SessionInfo.BurnStatus
                switch burnRate {
                case ..<10:     burnStatus = .idle
                case ..<500:    burnStatus = .low
                case ..<5000:   burnStatus = .normal
                case ..<20000:  burnStatus = .high
                default:        burnStatus = .extreme
                }

                // Cost for this session
                let sessionCost = session.modelBreakdown.values.reduce(0.0) {
                    $0 + CostCalculator.cost(for: $1)
                }

                // Projection
                let projectedTokens = Int(burnRate * sessionMinutes)
                let projectedCost = elapsedMinutes > 0.1
                    ? sessionCost * (sessionMinutes / elapsedMinutes) : 0

                let projectionStatus: SessionInfo.ProjectionStatus
                switch projectedCost {
                case ..<10:   projectionStatus = .onTrack
                case ..<50:   projectionStatus = .elevated
                default:      projectionStatus = .high
                }

                let models = session.models.sorted().map { shortModelName($0) }

                return SessionInfo(
                    sourceFile: session.sourceFile,
                    displayName: Self.displayName(for: session.sourceFile),
                    isActive: active,
                    sessionStart: session.firstRecord,
                    lastActivity: session.lastRecord,
                    elapsedSeconds: elapsed,
                    totalTokens: session.totalTokens,
                    estimatedCost: sessionCost,
                    burnRatePerMinute: burnRate,
                    burnStatus: burnStatus,
                    projectedTokens: projectedTokens,
                    projectedCost: projectedCost,
                    projectionStatus: projectionStatus,
                    activeModels: models
                )
            }
            .sorted { lhs, rhs in
                // Active sessions first, then by most recent activity
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                return (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast)
            }
    }

    /// Derive a short display name from a JSONL file path.
    /// e.g. "~/.claude/projects/-Users-chris-myproject/abc.jsonl" → "myproject"
    private static func displayName(for path: String) -> String {
        // The parent directory is a hash of the project path, often like:
        // -Users-chris-Code-myproject  →  extract last component
        let url = URL(fileURLWithPath: path)
        let dirName = url.deletingLastPathComponent().lastPathComponent
        // Split on hyphens, take the last meaningful segment(s)
        let parts = dirName.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            // Skip leading empty segments from paths like "-Users-..."
            let meaningful = parts.filter { !$0.isEmpty && $0.lowercased() != "users" }
            if let last = meaningful.last {
                return last
            }
        }
        // Fallback: use the JSONL filename without extension
        return url.deletingPathExtension().lastPathComponent
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
            liveSessions: buildLiveSessions(),
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
