import SwiftUI

/// The one button shape in the app. `primary` is the single action a screen is for; there
/// is never more than one on screen.
package struct ConsoleButtonStyle: ButtonStyle {
    var primary = false
    var ghost = false

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.text(12, primary ? .semibold : .medium))
            .foregroundStyle(primary ? Theme.bg : (ghost ? Theme.tx2 : Theme.prose))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? Theme.accent : (ghost ? .clear : Theme.raised))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        primary ? Theme.accent : (ghost ? .clear : Theme.controlLine),
                        lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == ConsoleButtonStyle {
    package static var console: ConsoleButtonStyle { ConsoleButtonStyle() }
    static var consolePrimary: ConsoleButtonStyle { ConsoleButtonStyle(primary: true) }
    package static var consoleGhost: ConsoleButtonStyle { ConsoleButtonStyle(ghost: true) }
}
