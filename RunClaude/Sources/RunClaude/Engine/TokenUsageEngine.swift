import Foundation
import Combine

// MARK: - Token Usage Engine

/// The central engine that ties together file watching, parsing, aggregation,
/// and cost alerting.
///
/// Publishes a `UsageState` that the UI layer observes to drive animation and stats.
final class TokenUsageEngine: ObservableObject {

    /// The current usage state, observed by the UI.
    @Published var state = UsageState()

    private let watcher: LogFileWatcher
    private let aggregator: TokenAggregator
    private let costAlertManager = CostAlertManager()
    private let configReader = ClaudeConfigReader()

    /// Timer to periodically recalculate velocity (even when no new data arrives,
    /// the sliding window needs to decay old samples).
    private var velocityTimer: Timer?

    // MARK: - Init

    init(scanInterval: TimeInterval = 2.0, windowDuration: TimeInterval = 20.0) {
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
        updateState()
    }

    private func updateState() {
        state = aggregator.buildState()
        state.claudeProfile = configReader.readProfile()
        // todayUsage already has estimatedCost populated by aggregator.buildState()
        costAlertManager.checkCost(state.todayUsage.estimatedCost)
    }
}
