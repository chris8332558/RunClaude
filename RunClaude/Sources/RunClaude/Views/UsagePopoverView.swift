import SwiftUI
import Charts

// MARK: - Usage Popover View

/// The main popover shown when clicking the menu bar icon.
/// Displays today's token usage, cost estimate, model breakdown, and a sparkline.
struct UsagePopoverView: View {
    @ObservedObject var engine: TokenUsageEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerSection

            Divider()

            // Live status
            liveStatusSection

            Divider()

            // Today's usage
            todayUsageSection

            Divider()

            // Model breakdown
            modelBreakdownSection

            Divider()

            // Sparkline
            sparklineSection

            Spacer()

            // Footer
            footerSection
        }
        .padding(16)
        .frame(width: 300, height: 420)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Text("RunClaude")
                .font(.headline)
            Spacer()
            Text(CostCalculator.formatCost(engine.state.todayUsage.estimatedCost))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
        }
    }

    private var liveStatusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.state.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(engine.state.isActive ? "Active" : "Idle")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if engine.state.tokensPerSecond >= 1 {
                Text("\(Int(engine.state.tokensPerSecond)) tok/s")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }

    private var todayUsageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.subheadline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Models")
                .font(.subheadline)
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
                            .frame(width: 8, height: 8)
                        Text(shortModelName(model))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(formatTokenCount(usage.totalTokens))
                            .font(.system(.caption, design: .monospaced))
                        Text(CostCalculator.formatCost(usage.estimatedCost))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Activity (last 6h)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            let data = engine.state.recentSamples
            if data.isEmpty {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 40)
                    .overlay(
                        Text("No recent activity")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    )
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

    private var footerSection: some View {
        HStack {
            Text("RunClaude v0.1.0")
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

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func shortModelName(_ model: String) -> String {
        // "claude-sonnet-4-20250514" → "Sonnet 4"
        let lower = model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        // Strip date suffix if present
        let parts = model.split(separator: "-")
        if parts.count > 2 {
            return parts.prefix(3).joined(separator: "-")
        }
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
