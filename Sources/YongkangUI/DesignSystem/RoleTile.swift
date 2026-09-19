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
        if r.contains("design") { return "ds" }
        if r.contains("product") { return "pr" }
        return String(r.prefix(2))
    }

    static func color(of role: String) -> Color {
        let r = role.lowercased()
        if r.contains("design") { return Theme.violet }
        if r.contains("work") { return Theme.accent }
        return Theme.tx2
    }

    private var color: Color { RoleTile.color(of: role) }
}
