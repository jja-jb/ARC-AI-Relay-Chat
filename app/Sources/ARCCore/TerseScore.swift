import Foundation

public extension ARCTerse {
    /// Explicit import, no provider integration, telemetry, guessed tokenizer,
    /// credentials, or hidden collection. Money is integer micro-US dollars.
    static func score(_ request: ARCJSONValue) throws -> ARCJSONValue {
        let root = try object(request)
        try exact(root, ["runs"])
        let runs = try array(root["runs"], maximum: 128)
        var pairs: [String: [String: [String: ARCJSONValue]]] = [:]
        let metrics = ["input_tokens", "output_tokens", "cached_input_tokens", "reasoning_tokens", "cost_microusd", "calls", "clarifications", "retries"]
        for run in runs {
            let r = try object(run)
            try exact(r, Set(metrics + ["pair", "variant", "model", "correct", "usage_source", "includes_all_costs"]))
            let pair = try name(r["pair"]), variant = try string(r["variant"])
            try choice(r["variant"], ["terse", "english"])
            try choice(r["usage_source"], ["reported_actual", "estimate"])
            guard !(try string(r["model"])).isEmpty, r["correct"]?.boolValue != nil,
                  r["includes_all_costs"]?.boolValue == true else { throw fail("include setup, context, tools, repairs and failed attempts; correctness must be explicit.") }
            for metric in metrics {
                guard let value = r[metric]?.integerValue, (0...1_000_000_000_000).contains(value) else { throw fail("metrics must be integers between 0 and 1000000000000; unavailable is not zero.") }
            }
            guard r["calls"]!.integerValue! > 0,
                  r["cached_input_tokens"]!.integerValue! <= r["input_tokens"]!.integerValue!,
                  r["reasoning_tokens"]!.integerValue! <= r["output_tokens"]!.integerValue! else { throw fail("cache/reasoning are subsets of input/output, not extra tokens; calls must be positive.") }
            guard pairs[pair]?[variant] == nil else { throw fail("duplicate variant in a matched pair.") }
            pairs[pair, default: [:]][variant] = r
        }
        var groups: [String: [String: Int64]] = [:]
        for pair in pairs.values {
            guard let terse = pair["terse"], let english = pair["english"], terse["model"] == english["model"], terse["usage_source"] == english["usage_source"] else { throw fail("each pair needs both variants with the same model and measurement basis.") }
            for (variant, run) in pair {
                let key = try string(run["usage_source"]) + ":" + variant
                groups[key, default: [:]]["runs", default: 0] += 1
                groups[key, default: [:]]["correct", default: 0] += run["correct"]!.boolValue! ? 1 : 0
                for metric in metrics { groups[key, default: [:]][metric, default: 0] += run[metric]!.integerValue! }
            }
        }
        let totals = groups.mapValues { values -> ARCJSONValue in
            var v = values.mapValues(ARCJSONValue.integer)
            let count = values["correct"] ?? 0
            v["cost_per_correct_microusd"] = count > 0 ? .integer(values["cost_microusd"]! / count) : .null
            return .object(v)
        }
        var comparisons: [String: ARCJSONValue] = [:]
        for basis in ["reported_actual", "estimate"] {
            if let t = groups[basis + ":terse"], let e = groups[basis + ":english"] {
                comparisons[basis] = .object([
                    "cost_difference_microusd": .integer(t["cost_microusd"]! - e["cost_microusd"]!),
                    "correct_difference": .integer(t["correct"]! - e["correct"]!),
                    "lower_cost_without_observed_accuracy_loss": .boolean(t["cost_microusd"]! < e["cost_microusd"]! && t["correct"]! >= e["correct"]!)
                ])
            }
        }
        return .object(["paired_tasks": .integer(Int64(pairs.count)), "totals": .object(totals), "comparisons": .object(comparisons),
            "caveat": .string("Imported figures are not independently verified. Keep workloads, tools, model settings and correctness criteria matched. No statistical significance or future savings is established. Cost per correct task includes failed runs and rounds down to a micro-US dollar. Cached/reasoning tokens are subsets; do not double count.")])
    }
}
