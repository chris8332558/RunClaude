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
        case month = "Month"
        case profile = "Profile"
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
                historyTab(data: engine.state.monthlyHistory, title: "Last 30 Days", isMonthly: true)
            case .profile:
                profileTab
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
        let sessions = engine.state.liveSessions
        let activeSessions = sessions.filter { $0.isActive }
        let totalTokens = sessions.reduce(0) { $0 + $1.totalTokens }
        let totalCost = sessions.reduce(0.0) { $0 + $1.estimatedCost }

        return VStack(alignment: .leading, spacing: 6) {
            // Summary header
            HStack(spacing: 12) {
                liveStatChip(
                    value: "\(activeSessions.count)/\(sessions.count)",
                    label: "active",
                    color: activeSessions.isEmpty ? .gray : .green
                )
                liveStatChip(
                    value: formatTokenCount(totalTokens),
                    label: "tokens",
                    color: .cyan
                )
                liveStatChip(
                    value: CostCalculator.formatCost(totalCost),
                    label: "cost",
                    color: .orange
                )
            }

            Divider()

            if sessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No sessions detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Start a Claude Code session to see live stats")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                }
                Spacer()
            } else {
                // Scrollable session list
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(sessions) { session in
                            liveSessionCard(session)
                        }
                    }
                }
            }

            // Footer refresh indicator
            HStack {
                Spacer()
                Text("Refreshing every 0.5s")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.secondary.opacity(0.5))
                Circle()
                    .fill(engine.state.isActive ? Color.green : Color.gray)
                    .frame(width: 5, height: 5)
                Spacer()
            }
        }
    }

    /// A compact card for a single live session.
    private func liveSessionCard(_ session: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: project name + active badge + time
            HStack(spacing: 4) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(session.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                if session.isActive {
                    liveStatusBadge("LIVE", color: .green)
                }
                Spacer()
                Text(formatTime(session.sessionStart))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Progress bar: tokens vs projected
            let progress = session.projectedTokens > 0
                ? min(Double(session.totalTokens) / Double(session.projectedTokens), 1.0)
                : 0.0
            liveProgressBar(value: progress, color: session.isActive ? .green : .gray)

            // Stats row 1: tokens + cost
            HStack {
                Text("Tokens: \(formatTokenCount(session.totalTokens))")
                    .font(.system(size: 9, design: .monospaced))
                Spacer()
                Text("Burn: \(formatBurnRate(session.burnRatePerMinute)) tok/min")
                    .font(.system(size: 9, design: .monospaced))
                liveStatusBadge(session.burnStatus.rawValue, color: burnStatusColor(session.burnStatus))
            }

            // Stats row 2: cost + projection + models
            HStack {
                Text("Cost: \(CostCalculator.formatCost(session.estimatedCost))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Proj: \(formatTokenCount(session.projectedTokens)) / \(CostCalculator.formatCost(session.projectedCost))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                liveStatusBadge(session.projectionStatus.rawValue, color: projectionStatusColor(session.projectionStatus))
            }

            // Models row
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(session.activeModels.isEmpty ? "—" : session.activeModels.joined(separator: ", "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(session.isActive ? 0.6 : 0.3))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(session.isActive ? Color.green.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }

    /// A small stat chip for the summary header.
    private func liveStatChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Live Session Helpers

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
            Text("Activity (today)")
                .font(.caption)
                .foregroundColor(.secondary)

            let rawData = engine.state.sparklineBuckets
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())
            let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

            // Aggregate 5-min buckets into 30-min buckets (48 bars for 24h)
            let halfHourBuckets = aggregateToHalfHour(rawData, dayStart: todayStart)

            if halfHourBuckets.isEmpty {
                emptyChartPlaceholder(text: "No recent activity")
            } else {
                // Build the 5 axis mark dates: 0h, 6h, 12h, 18h, 23h
                let axisHours = [0, 6, 12, 18]
                let axisDates = axisHours.map { calendar.date(byAdding: .hour, value: $0, to: todayStart)! }

                Chart {
                    ForEach(halfHourBuckets, id: \.date) { bucket in
                        BarMark(
                            x: .value("Time", bucket.date),
                            y: .value("Tokens", bucket.tokens)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                }
                .chartXScale(domain: todayStart...todayEnd)
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                // Hours since midnight (handles 24 correctly)
                                let hours = Int(date.timeIntervalSince(todayStart) / 3600)
                                Text("\(hours)")
                                    .font(.system(size: 8))
                            }
                        }
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.2))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(formatTokenCount(v))
                                    .font(.system(size: 7))
                            }
                        }
                    }
                }
                .frame(height: 50)
            }
        }
    }

    /// Aggregate 5-minute sparkline buckets into 30-minute buckets for a cleaner chart.
    private func aggregateToHalfHour(_ buckets: [SparklineBucket], dayStart: Date) -> [SparklineBucket] {
        guard !buckets.isEmpty else { return [] }
        let halfHour: TimeInterval = 1800
        var grouped: [Date: Int] = [:]

        for bucket in buckets {
            let offset = bucket.date.timeIntervalSince(dayStart)
            let slotOffset = (offset / halfHour).rounded(.down) * halfHour
            let slotDate = dayStart.addingTimeInterval(slotOffset)
            grouped[slotDate, default: 0] += bucket.tokens
        }

        return grouped
            .map { SparklineBucket(date: $0.key, tokens: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - History Tab (Week / Month)

    private func historyTab(data: [HistoryDataPoint], title: String, isMonthly: Bool = false) -> some View {
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

            // Compute which indices get x-axis labels
            // For monthly: show ~4 evenly spaced labels; for weekly: show all
            let labelIndices: Set<Int> = {
                if !isMonthly || data.count <= 7 {
                    return Set(0..<data.count)
                }
                // 4 labels: first, ~1/3, ~2/3, last
                let count = data.count
                return [0, count / 3, 2 * count / 3, count - 1]
            }()

            let indexed = Array(data.enumerated())

            // Token chart
            VStack(alignment: .leading, spacing: 4) {
                Text("Tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if totalTokens == 0 {
                    emptyChartPlaceholder(text: "No usage data for this period")
                } else {
                    Chart(indexed, id: \.offset) { index, point in
                        BarMark(
                            x: .value("Date", "\(index)"),
                            y: .value("Tokens", point.totalTokens),
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                        .cornerRadius(4) // Optional: makes it look modern
                    }
                    .chartXAxis {
                        // 1. Convert your labelIndices (Ints) to the same String format used in BarMark
                        let stringValues = labelIndices.map { "\($0)" }
                        AxisMarks(values: stringValues) { value in
                            if let labelString = value.as(String.self),
                            let idx = Int(labelString),
                            idx < data.count {
                                AxisValueLabel {
                                    Text(data[idx].label)
                                        .font(.system(size: 8))
                                }
                            }
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
                    Chart(indexed, id: \.offset) { index, point in
                        BarMark(
                            x: .value("Date", "\(index)"),
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

    // MARK: - Profile Tab

    private var profileTab: some View {
        let profile = engine.state.claudeProfile

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                // Account section
                profileAccountSection(profile)

                Divider()
                
                // Skills section
                profileSkillsSection(profile)

                Divider()

                // Tool usage section
                profileToolUsageSection(profile)

                Divider()

                // Plugins section
                profilePluginsSection(profile)


            }
        }
    }

    private func profileAccountSection(_ profile: ClaudeProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("Account")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            // Prominent stats at the top — two rows
            if let days = profile.daysSinceFirstUse {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                    Text("\(days)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    Text("days with Claude Code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            let lifetime = engine.state.lifetimeTotalTokens
            if lifetime > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                    Text(formatTokenCount(lifetime))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    Text("tokens with Claude Code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            if let account = profile.account {
                VStack(alignment: .leading, spacing: 4) {
                    profileRow(label: "Name", value: account.displayName)
                    profileRow(label: "Email", value: account.emailAddress)
                    profileRow(label: "Org", value: account.organizationName)
                    profileRow(label: "Role", value: account.organizationRole)
                    HStack(spacing: 6) {
                        profileRow(label: "Plan", value: account.billingLabel)
                        if account.hasExtraUsageEnabled {
                            Text("+ Extended")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }
                }
            } else {
                Text("No account info found")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                Text("Expected at ~/.claude.json")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    private func profileToolUsageSection(_ profile: ClaudeProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("Tool Usage")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                if profile.totalToolInvocations > 0 {
                    Text("\(formatToolCount(profile.totalToolInvocations)) total")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if profile.toolUsage.isEmpty {
                Text("No tool usage data")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                // Show top tools as horizontal bar chart
                let topTools = Array(profile.toolUsage.prefix(8))
                let maxCount = topTools.first?.usageCount ?? 1

                ForEach(topTools) { tool in
                    HStack(spacing: 6) {
                        Text(tool.toolName)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 70, alignment: .trailing)

                        GeometryReader { geo in
                            let barWidth = max(
                                geo.size.width * CGFloat(tool.usageCount) / CGFloat(maxCount),
                                2
                            )
                            RoundedRectangle(cornerRadius: 2)
                                .fill(toolColor(tool.toolName))
                                .frame(width: barWidth, height: 12)
                        }
                        .frame(height: 12)

                        Text("\(tool.usageCount)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func profilePluginsSection(_ profile: ClaudeProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                Text("Plugins")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(profile.installedPlugins.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if profile.installedPlugins.isEmpty {
                Text("No plugins installed")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                Text("Install plugins via claude plugins add")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                ForEach(profile.installedPlugins) { plugin in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(plugin.enabled ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                        Text(plugin.name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        if let version = plugin.version {
                            Text("v\(version)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !plugin.enabled {
                            Text("OFF")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(2)
                        }
                    }

                    if let desc = plugin.description {
                        Text(desc)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(2)
                            .padding(.leading, 11)
                    }
                }
            }
        }
    }

    private func profileSkillsSection(_ profile: ClaudeProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan)
                Text("Skills")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(profile.installedSkills.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if profile.installedSkills.isEmpty {
                Text("No skills installed")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                // Group skills by marketplace
                let grouped = Dictionary(grouping: profile.installedSkills) { $0.marketplace }
                let sortedMarketplaces = grouped.keys.sorted()

                ForEach(sortedMarketplaces, id: \.self) { marketplace in
                    if sortedMarketplaces.count > 1 {
                        Text(marketplace)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 2)
                    }

                    let skills = grouped[marketplace] ?? []
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], alignment: .leading, spacing: 4) {
                        ForEach(skills) { skill in
                            Text(skill.name)
                                .font(.system(size: 9, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Profile Helpers

    private func profileRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
        }
    }

    private func toolColor(_ name: String) -> Color {
        switch name {
        case "Read":   return .blue
        case "Write":  return .green
        case "Edit":   return .orange
        case "Bash":   return .red
        case "Glob":   return .cyan
        case "Grep":   return .teal
        case "Agent":  return .purple
        default:       return .accentColor.opacity(0.7)
        }
    }

    private func formatToolCount(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
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
        VStack(alignment: .center, spacing: 2) {
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
