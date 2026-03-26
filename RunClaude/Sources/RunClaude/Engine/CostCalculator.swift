import Foundation

// MARK: - Cost Calculator

/// Estimates USD cost from token counts using known Claude model pricing.
///
/// Pricing is hardcoded for now. A future version could fetch live pricing
/// from the LiteLLM API (like ccusage does) with an offline fallback.
struct CostCalculator {

    /// Pricing per million tokens for each model family.
    struct ModelPricing {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheCreationPerMillion: Double
        let cacheReadPerMillion: Double
    }

    /// Known model pricing (as of early 2026).
    /// Keys are model name prefixes for flexible matching.
    static let pricing: [(prefix: String, pricing: ModelPricing)] = [
        // Claude Opus 4
        ("claude-opus-4", ModelPricing(
            inputPerMillion: 15.0,
            outputPerMillion: 75.0,
            cacheCreationPerMillion: 18.75,
            cacheReadPerMillion: 1.50
        )),
        // Claude Sonnet 4
        ("claude-sonnet-4", ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheCreationPerMillion: 3.75,
            cacheReadPerMillion: 0.30
        )),
        // Claude Haiku 3.5
        ("claude-haiku", ModelPricing(
            inputPerMillion: 0.80,
            outputPerMillion: 4.0,
            cacheCreationPerMillion: 1.0,
            cacheReadPerMillion: 0.08
        )),
        // Claude 3.5 Sonnet (legacy)
        ("claude-3-5-sonnet", ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheCreationPerMillion: 3.75,
            cacheReadPerMillion: 0.30
        )),
        // Claude 3 Opus (legacy)
        ("claude-3-opus", ModelPricing(
            inputPerMillion: 15.0,
            outputPerMillion: 75.0,
            cacheCreationPerMillion: 18.75,
            cacheReadPerMillion: 1.50
        )),
    ]

    /// Default pricing for unknown models (Sonnet-tier as a safe middle ground).
    static let defaultPricing = ModelPricing(
        inputPerMillion: 3.0,
        outputPerMillion: 15.0,
        cacheCreationPerMillion: 3.75,
        cacheReadPerMillion: 0.30
    )

    /// Calculate the estimated cost for a token record.
    static func cost(for record: TokenRecord) -> Double {
        let p = findPricing(for: record.model)
        return calculateCost(
            inputTokens: record.inputTokens,
            outputTokens: record.outputTokens,
            cacheCreationTokens: record.cacheCreationTokens,
            cacheReadTokens: record.cacheReadTokens,
            pricing: p
        )
    }

    /// Calculate the estimated cost for a model usage breakdown.
    static func cost(for usage: ModelUsage) -> Double {
        let p = findPricing(for: usage.model)
        return calculateCost(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheCreationTokens: usage.cacheCreationTokens,
            cacheReadTokens: usage.cacheReadTokens,
            pricing: p
        )
    }

    /// Format a cost as a human-readable string.
    static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1.0 {
            return String(format: "$%.3f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    // MARK: - Private

    private static func findPricing(for model: String) -> ModelPricing {
        let lowered = model.lowercased()
        for entry in pricing {
            if lowered.hasPrefix(entry.prefix) || lowered.contains(entry.prefix) {
                return entry.pricing
            }
        }
        return defaultPricing
    }

    private static func calculateCost(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        pricing: ModelPricing
    ) -> Double {
        let input = Double(inputTokens) * pricing.inputPerMillion / 1_000_000
        let output = Double(outputTokens) * pricing.outputPerMillion / 1_000_000
        let cacheCreate = Double(cacheCreationTokens) * pricing.cacheCreationPerMillion / 1_000_000
        let cacheRead = Double(cacheReadTokens) * pricing.cacheReadPerMillion / 1_000_000
        return input + output + cacheCreate + cacheRead
    }
}
