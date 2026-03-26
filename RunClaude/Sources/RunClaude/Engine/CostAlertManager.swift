import Foundation
import UserNotifications

// MARK: - Cost Alert Manager

/// Monitors daily cost and sends a macOS notification when a user-defined threshold is exceeded.
///
/// The alert fires at most once per day per threshold crossing.
/// Resets at midnight.
final class CostAlertManager {

    /// The UserDefaults key for the cost threshold (in USD).
    static let thresholdKey = "costAlertThreshold"

    /// The UserDefaults key for whether alerts are enabled.
    static let enabledKey = "costAlertEnabled"

    /// The date when the last alert was fired (to avoid repeated alerts in one day).
    private var lastAlertDate: Date?

    // MARK: - Init

    init() {
        requestNotificationPermission()
    }

    // MARK: - Check & Alert

    /// Call this whenever the daily cost is updated.
    /// If alerts are enabled and the threshold is exceeded, send a notification.
    func checkCost(_ dailyCost: Double) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }

        let threshold = UserDefaults.standard.double(forKey: Self.thresholdKey)
        guard threshold > 0, dailyCost >= threshold else { return }

        // Only alert once per day
        let today = Calendar.current.startOfDay(for: Date())
        if let last = lastAlertDate, Calendar.current.startOfDay(for: last) == today {
            return
        }

        lastAlertDate = Date()
        sendNotification(cost: dailyCost, threshold: threshold)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[RunClaude] Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func sendNotification(cost: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "RunClaude — Cost Alert"
        content.body = "Today's Claude usage has reached \(CostCalculator.formatCost(cost)), exceeding your \(CostCalculator.formatCost(threshold)) threshold."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "cost-alert-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[RunClaude] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
