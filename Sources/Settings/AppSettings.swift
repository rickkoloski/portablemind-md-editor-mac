import SwiftUI

/// Persistent app preferences. UserDefaults-backed via `@AppStorage`
/// so preference changes propagate as SwiftUI state automatically.
///
/// Storage per `docs/stack-alternatives.md` § "Explicitly not using":
/// no Core Data / SwiftData. Every setting here is a primitive value
/// suitable for UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Backed by UserDefaults key `toolbarVisible`. Default true per
    /// `docs/vision.md` Principle 1: the formatting toolbar is on by
    /// default for the priority-1 audience (Word/Docs users).
    @AppStorage("toolbarVisible") var toolbarVisible: Bool = true

    private init() {}
}
