import SwiftUI

package struct YongkangApp: App {
    @State private var model = AppModel()

    package init() {}

    package var body: some Scene {
        WindowGroup {
            // Nothing on a clock here any more: `RootView` starts each project's FSEvents watch
            // and the 30 s safety poll behind them. See `AppModel.start(polling:)`.
            RootView(model: model)
        }
        .windowToolbarStyle(.unified)
        // One window: the model and its TerminalRegistry are app-wide, so a second window
        // would take the first one's terminals. Not a `Window` scene, because closing that
        // quits the app and every agent with it. Dropping New Window also frees ⌘N for the
        // "Describe a new project" tile.
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
