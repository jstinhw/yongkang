import Foundation
import YongkangCore

/// The app shell's way in, and the only `public` declaration in the package. Xcode compiles
/// `App/Yongkang.xcodeproj` without this package's `-package-name` (which comes from the
/// checkout's folder name, so it differs in every worktree), so no `package` API is visible
/// there.
public enum YongkangMain {
    @MainActor public static func run() {
        if let old = UserDefaults(suiteName: DefaultsMigration.oldDomain) {
            DefaultsMigration.run(from: old, to: .standard)
        }
        YongkangApp.main()
    }
}
