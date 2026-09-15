import SwiftUI

extension AgentUsage {
    /// A bar's colour is its headroom, not its provider: the point of the number is how
    /// close the work is to stopping.
    static func tint(_ percent: Double) -> Color {
        switch percent {
        case 90...: return Theme.red
        case 70...: return Theme.amber
        default: return Theme.green
        }
    }

    /// One colour per model family, held steady across every panel so a slice in the model
    /// bar and a label on an agent row are recognisably the same thing.
    static func modelTint(_ model: String) -> Color {
        switch family(model) {
        case "opus": return Theme.violet
        case "sonnet": return Theme.accent
        case "haiku": return Theme.green
        case "fable": return Theme.amber
        default: return Theme.tx3
        }
    }

    /// A colour per model for one render, rather than per family. Two versions of the same
    /// model are the same hue at different weights: a bar stacked out of one flat violet
    /// says how much went to Opus but not which Opus, which is half the question. Pass the
    /// models biggest-spender first, so the one that did most of the work is full strength.
    static func palette(for models: [String]) -> [String: Color] {
        var depth: [String: Int] = [:]
        return models.reduce(into: [:]) { palette, model in
            let step = depth[family(model), default: 0]
            depth[family(model)] = step + 1
            palette[model] =
                step == 0
                ? modelTint(model)
                : modelTint(model).opacity(1 - 0.32 * Double(min(step, 2)))
        }
    }
}
