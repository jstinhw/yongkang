import SwiftUI

/// A dot that says whether something is live, in the same colour language as everything
/// else. The ring is what separates "running right now" from a static status.
struct StateDot: View {
    var color: Color = Theme.accent
    var live = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay {
                if live {
                    Circle().strokeBorder(color.opacity(0.35), lineWidth: 1).padding(-4)
                }
            }
    }
}
