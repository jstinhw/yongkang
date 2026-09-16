import SwiftUI
import YongkangCore

package struct YongkangApp: App {
    @State private var model = AppModel()
    /// The two settings the menu bar shares with the window. `@AppStorage` is a view of one
    /// UserDefaults key, so these and `RootView`'s are the same switch rather than two copies
    /// that could disagree.
    @AppStorage("listHidden") private var listHidden = false
    @AppStorage("agentKind") private var agent = AgentKind.claude

    package init() {
        _ = TextKeys.monitor
    }

    package var body: some Scene {
        WindowGroup {
            // Nothing on a clock here any more: `RootView` starts each project's FSEvents watch
            // and the 30 s safety poll behind them. See `AppModel.start(polling:)`.
            RootView(model: model)
        }
        .windowToolbarStyle(.unified)
        // One window: the model and its TerminalRegistry are app-wide, so a second window
        // would take the first one's terminals. Not a `Window` scene, because closing that
        // quits the app and every agent with it. `YongkangCommands` replaces the `.newItem`
        // group, which is what drops New Window and frees ⌘N.
        .commands { YongkangCommands(model: model, listHidden: $listHidden, agent: agent) }
    }
}
