import SwiftUI
import YongkangCore

extension ReviewArea {
    var color: Color {
        switch self {
        case .database: return Theme.amber
        case .api: return Theme.green
        case .frontend: return Theme.accent
        case .tests: return Theme.violet
        case .config, .other: return Theme.tx2
        case .notebook: return Theme.tx3
        }
    }
}
