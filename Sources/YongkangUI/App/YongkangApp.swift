import Combine
import SwiftUI

package struct YongkangApp: App {
    @State private var model = AppModel()

    // ponytail: poll instead of an FSEvents watcher. The agents in the console write
    // these files while you watch them; re-listing a few dozen paths every 2s is less
    // code than a recursive watcher and the tree is tiny. Revisit at thousands of files.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    package init() {}

    package var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onReceive(tick) { _ in model.reload() }
        }
        .windowToolbarStyle(.unified)
    }
}
