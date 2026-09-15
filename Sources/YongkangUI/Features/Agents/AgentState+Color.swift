import SwiftUI
import YongkangCore

extension AgentState {
    var color: Color {
        switch self {
        case .starting, .working: return Theme.accent
        case .waiting: return Theme.amber
        case .done: return Theme.green
        case .exited: return Theme.tx3
        }
    }
}
