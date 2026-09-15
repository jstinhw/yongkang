import Foundation

/// The bundle ID moved from `local.yongkang.app` to `ai.yongkang.Yongkang` (refactor plan D9),
/// and a new bundle ID starts with an empty defaults domain. This carries over the settings
/// you'd notice losing, above all the open projects.
package enum DefaultsMigration {
    package static let oldDomain = "local.yongkang.app"
    static let keys = ["openProjects", "listWidth", "listHidden", "agentKind"]

    /// Fills only the keys `new` doesn't have yet. It never undoes a change made after the
    /// move, and every launch after the first is a no-op.
    package static func run(from old: UserDefaults, to new: UserDefaults) {
        for key in keys where new.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                new.set(value, forKey: key)
            }
        }
    }
}
