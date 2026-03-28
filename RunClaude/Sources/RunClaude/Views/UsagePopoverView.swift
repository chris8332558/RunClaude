import SwiftUI
import Charts

// MARK: - Usage Popover View

/// The main popover shown when clicking the menu bar icon.
/// Features a tab bar to switch between Today, Week, and Month views.
struct UsagePopoverView: View {
    @ObservedObject var engine: TokenUsageEngine
    @State private var selectedTab: PopoverTab = .live

    enum PopoverTab: String, CaseIterable {
        case live = "Live"
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
            case .live:
                liveSessionTab
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
        .frame(width: 320, height: 480)
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

    // MARK: - Live Session Tab

    private var liveSessionTab: some View {
        let session = engine.state.sessionInfo
        let usage = engine.state.todayUsage

        return VStack(alignment: .leading, spacing: 8) {
            // SESSION block
            liveBlock(icon: "circle.fill", iconColor: engine.state.isActive ? .cyan : .gray, title: "SESSION") {
                VStack(alignment: .leading, spacing: 4) {
                    // Progress bar
                    let sessionHours: Double = 8.0
                    let progress = min(session.elapsedSeconds / (sessionHours * 3600), 1.0)
                    liveProgressBar(value: progress, color: .cyan)

                    HStack {
                        Text("Started: \(formatTime(session.sessionStart))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        let remaining = max(sessionHours - session.elapsedSeconds / 3600, 0)
                        Text(String(format: "%.1fh left", remaining))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // USAGE block
            liveBlock(icon: "flame.fill", iconColor: .orange, title: "USAGE") {
                VStack(alignment: .leading, spacing: 4) {
                    // Token progress bar (scaled to projected)
                    let tokenProgress = session.projectedTokens > 0
                        ? min(Double(usage.totalTokens) / Double(session.projectedTokens), 1.0)
                        : 0.0
                    liveProgressBar(value: tokenProgress, color: .green)

                    HStack {
                        Text("Tokens: \(formatTokenCount(usage.totalTokens))")
                            .font(.system(size: 10, design: .monospaced))
                        Spacer()
                        Text("(\(formatTokenCount(session.projectedTokens)) proj)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Burn Rate: \(formatBurnRate(session.burnRatePerMinute)) tok/min")
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.semibold)
                        liveStatusBadge(session.burnStatus.rawValue, color: burnStatusColor(session.burnStatus))
                        Spacer()
                        Text("Cost: \(CostCalculator.formatCost(usage.estimatedCost))")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }

            // PROJECTION block
            liveBlock(icon: "chart.line.uptrend.xyaxis", iconColor: .green, title: "PROJECTION") {
                VStack(alignment: .leading, spacing: 4) {
                    let projProgress = session.projectedTokens > 0
                        ? min(Double(usage.totalTokens) / Double(session.projectedTokens), 1.0)
                        : 0.0
                    liveProgressBar(value: projProgress, color: projectionStatusColor(session.projectionStatus))

                    HStack {
                        liveStatusBadge(session.projectionStatus.rawValue, color: projectionStatusColor(session.projectionStatus))
                        Spacer()
                        Text("Tokens: \(formatTokenCount(session.projectedTokens))")
                            .font(.system(size: 10, design: .monospaced))
                        Spacer()
                        Text("Cost: \(CostCalculator.formatCost(session.projectedCost))")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }

            // MODELS block
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("Models:")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(session.activeModels.isEmpty ? "none" : session.activeModels.joined(separator: ", "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)

            // Refresh indicator
            HStack {
                Spacer()
                Text("Refreshing every 0.5s")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.secondary.opacity(0.6))
                Circle()
                    .fill(engine.state.isActive ? Color.green : Color.gray)
                    .frame(width: 5, height: 5)
                Spacer()
            }
        }
    }

    // MARK: - Live Session Helpers

    private func liveBlock<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func liveProgressBar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 6)

                // Filled portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(geo.size.width * CGFloat(value), 0), height: 6)
            }
        }
        .frame(height: 6)
    }

    private func liveStatusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .cornerRadius(3)
    }

    private func burnStatusColor(_ status: SessionInfo.BurnStatus) -> Color {
        switch status {
        case .idle:    return .gray
        case .low:     return .blue
        case .normal:  return .green
        case .high:    return .orange
        case .extreme: return .red
        }
    }

    private func projectionStatusColor(_ status: SessionInfo.ProjectionStatus) -> Color {
        switch status {
        case .onTrack:  return .green
        case .elevated: return .orange
        case .high:     return .red
        }
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }

    private func formatBurnRate(_ rate: Double) -> String {
        if rate >= 1_000_000 {
            return String(format: "%.1fM", rate / 1_000_000)
        } else if rate >= 1_000 {
            return String(format: "%.0fK", rate / 1_000)
        }
        return String(format: "%.0f", rate)
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

            let data = engine.state.sparklineBuckets
            if data.isEmpty {
                emptyChartPlaceholder(text: "No recent activity")
            } else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, bucket in
                        BarMark(
                            x: .value("Time", index),
                            y: .value("Tokens", bucket.tokens)
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
