import Foundation
import Combine

// MARK: - Token Usage Engine

/// The central engine that ties together file watching, parsing, and aggregation.
///
/// Publishes a `UsageState` that the UI layer observes to drive animation and stats.
final class TokenUsageEngine: ObservableObject {

    /// The current usage state, observed by the UI.
    @Published var state = UsageState()

    private let watcher: LogFileWatcher
    private let aggregator: TokenAggregator

    /// Timer to periodically recalculate velocity (even when no new data arrives,
    /// the sliding window needs to decay old samples).
    private var velocityTimer: Timer?

    // MARK: - Init

    init(scanInterval: TimeInterval = 2.0, windowDuration: TimeInterval = 10.0) {
        self.watcher = LogFileWatcher(scanInterval: scanInterval)
        self.aggregator = TokenAggregator(windowDuration: windowDuration)

        watcher.onNewRecords = { [weak self] records in
            self?.handleNewRecords(records)
        }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        watcher.start()

        // Update velocity every 0.5s so the animation decays smoothly when idle
        velocityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateState()
        }
    }

    func stop() {
        watcher.stop()
        velocityTimer?.invalidate()
        velocityTimer = nil
    }

    // MARK: - Data Paths Info

    /// Returns the paths being watched, for display in settings/debug.
    var watchedPaths: [String] {
        LogFileWatcher.discoverClaudeDataPaths()
    }

    // MARK: - Private

    private func handleNewRecords(_ records: [TokenRecord]) {
        aggregator.ingest(records)

        // Update cost estimates
        var usage = aggregator.today
        for (model, var modelUsage) in usage.modelBreakdown {
            modelUsage.estimatedCost = CostCalculator.cost(for: modelUsage)
            usage.modelBreakdown[model] = modelUsage
        }
        usage.estimatedCost = usage.modelBreakdown.values.reduce(0) { $0 + $1.estimatedCost }

        updateState()
    }

    private func updateState() {
        state = aggregator.buildState()
        // Recalculate today's cost
        var today = aggregator.today
        var totalCost = 0.0
        for (model, var modelUsage) in today.modelBreakdown {
            modelUsage.estimatedCost = CostCalculator.cost(for: modelUsage)
            today.modelBreakdown[model] = modelUsage
            totalCost += modelUsage.estimatedCost
        }
        today.estimatedCost = totalCost
        state.todayUsage = today
    }
}
