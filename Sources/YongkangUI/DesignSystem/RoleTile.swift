import SwiftUI

/// A small square tile carrying a role's two-letter mark. The same colour follows a role
/// everywhere it appears, which is what lets a lane of agents be read without labels.
struct RoleTile: View {
    let role: String
    var size: CGFloat = 22

    var body: some View {
        Text(RoleTile.mark(role))
            .font(size < 26 ? Typography.monoCaption(.semibold) : Typography.mono(.semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size / 3).fill(color.opacity(0.14)))
            .overlay(
                RoundedRectangle(cornerRadius: size / 3)
                    .strokeBorder(color.opacity(0.28), lineWidth: 1))
    }

    static func mark(_ role: String) -> String {
        let r = role.lowercased()
        // Before frontend: the same agent runs both skills, and the design pass is the one
        // that has to be told apart on the board.
        if r.contains("design") { return "ds" }
        if r.contains("frontend") { return "fe" }
        if r.contains("backend") { return "be" }
        if r.contains("qa") { return "qa" }
        if r.contains("sre") { return "sre" }
        if r.contains("fde") { return "fde" }
        if r.contains("product") { return "pr" }
        if r.contains("lead") { return "EL" }
        return String(r.prefix(2))
    }

    static func color(of role: String) -> Color {
        let r = role.lowercased()
        if r.contains("design") { return Theme.violet }
        if r.contains("frontend") { return Theme.accent }
        if r.contains("backend") { return Theme.green }
        if r.contains("qa") { return Theme.violet }
        if r.contains("sre") || r.contains("fde") { return Theme.amber }
        return Theme.tx2
    }

    private var color: Color { RoleTile.color(of: role) }
}
