import SwiftUI
import Charts

// MARK: - Usage Popover View

/// The main popover shown when clicking the menu bar icon.
/// Features a tab bar to switch between Today, Week, and Month views.
struct UsagePopoverView: View {
    @ObservedObject var engine: TokenUsageEngine
    @State private var selectedTab: PopoverTab = .today

    enum PopoverTab: String, CaseIterable {
        case today = "Today"
        case week = "7 Days"
        case month = "30 Days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            headerSection

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(PopoverTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            // Tab content
            switch selectedTab {
            case .today:
                todayTab
            case .week:
                historyTab(data: engine.state.weeklyHistory, title: "Last 7 Days")
            case .month:
                historyTab(data: engine.state.monthlyHistory, title: "Last 30 Days")
            }

            Spacer(minLength: 0)

            // Footer
            footerSection
        }
        .padding(14)
        .frame(width: 320, height: 440)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.state.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("RunClaude")
                    .font(.headline)
            }
            Spacer()
            if engine.state.tokensPerSecond >= 1 {
                Text("\(Int(engine.state.tokensPerSecond)) tok/s")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(CostCalculator.formatCost(engine.state.todayUsage.estimatedCost))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
        }
    }

    // MARK: - Today Tab

    private var todayTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Token counts
            todayUsageSection

            Divider()

            // Model breakdown
            modelBreakdownSection

            Divider()

            // Activity sparkline
            sparklineSection
        }
    }

    private var todayUsageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                tokenStatView(label: "Input", value: engine.state.todayUsage.inputTokens)
                tokenStatView(label: "Output", value: engine.state.todayUsage.outputTokens)
                tokenStatView(label: "Cache Write", value: engine.state.todayUsage.cacheCreationTokens)
                tokenStatView(label: "Cache Read", value: engine.state.todayUsage.cacheReadTokens)
            }

            HStack {
                Text("Total")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTokenCount(engine.state.todayUsage.totalTokens))
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
            }
        }
    }

    private var modelBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models")
                .font(.caption)
                .foregroundColor(.secondary)

            let models = engine.state.todayUsage.modelBreakdown
                .sorted { $0.value.totalTokens > $1.value.totalTokens }

            if models.isEmpty {
                Text("No usage yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(models, id: \.key) { model, usage in
                    HStack {
                        Circle()
                            .fill(colorForModel(model))
                            .frame(width: 6, height: 6)
                        Text(shortModelName(model))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(formatTokenCount(usage.totalTokens))
                            .font(.system(.caption2, design: .monospaced))
                        Text(CostCalculator.formatCost(usage.estimatedCost))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Activity (last 6h)")
                .font(.caption)
                .foregroundColor(.secondary)

            let data = engine.state.recentSamples
            if data.isEmpty {
                emptyChartPlaceholder(text: "No recent activity")
            } else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, sample in
                        BarMark(
                            x: .value("Time", index),
                            y: .value("Tokens", sample.tokens)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 40)
            }
        }
    }

    // MARK: - History Tab (Week / Month)

    private func historyTab(data: [HistoryDataPoint], title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary stats
            let totalTokens = data.reduce(0) { $0 + $1.totalTokens }
            let totalCost = data.reduce(0.0) { $0 + $1.estimatedCost }
            let avgTokens = data.isEmpty ? 0 : totalTokens / data.count
            let maxDay = data.max(by: { $0.totalTokens < $1.totalTokens })

            HStack(spacing: 16) {
                summaryStatView(label: "Total", value: formatTokenCount(totalTokens))
                summaryStatView(label: "Cost", value: CostCalculator.formatCost(totalCost))
                summaryStatView(label: "Avg/day", value: formatTokenCount(avgTokens))
            }

            Divider()

            // Token chart
            VStack(alignment: .leading, spacing: 4) {
                Text("Tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if totalTokens == 0 {
                    emptyChartPlaceholder(text: "No usage data for this period")
                } else {
                    Chart(data) { point in
                        BarMark(
                            x: .value("Date", point.label),
                            y: .value("Tokens", point.totalTokens)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: data.count <= 7 ? data.count : 6)) { value in
                            AxisValueLabel()
                                .font(.system(size: 8))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel()
                                .font(.system(size: 8))
                            AxisGridLine()
                        }
                    }
                    .frame(height: 100)
                }
            }

            Divider()

            // Cost chart
            VStack(alignment: .leading, spacing: 4) {
                Text("Cost (USD)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if totalCost == 0 {
                    emptyChartPlaceholder(text: "No cost data")
                } else {
                    Chart(data) { point in
                        BarMark(
                            x: .value("Date", point.label),
                            y: .value("Cost", point.estimatedCost)
                        )
                        .foregroundStyle(Color.orange.opacity(0.8))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel(format: .currency(code: "USD").precision(.fractionLength(2)))
                                .font(.system(size: 8))
                            AxisGridLine()
                        }
                    }
                    .frame(height: 80)
                }
            }

            if let peak = maxDay, peak.totalTokens > 0 {
                Text("Peak: \(formatTokenCount(peak.totalTokens)) on \(peak.label)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("RunClaude v0.2.0")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func tokenStatView(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(formatTokenCount(value))
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func summaryStatView(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyChartPlaceholder(text: String) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .frame(height: 40)
            .overlay(
                Text(text)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            )
            .cornerRadius(4)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func shortModelName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        let parts = model.split(separator: "-")
        if parts.count > 2 { return parts.prefix(3).joined(separator: "-") }
        return model
    }

    private func colorForModel(_ model: String) -> Color {
        let lower = model.lowercased()
        if lower.contains("opus") { return .purple }
        if lower.contains("sonnet") { return .blue }
        if lower.contains("haiku") { return .orange }
        return .gray
    }
}
