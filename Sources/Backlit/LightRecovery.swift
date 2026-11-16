import Foundation

/// A lid journal belongs to a retained helper until its existing cleanup path
/// verifies handback. Without that owner, even an unreadable journal blocks a
/// new light session. Logo/fade journals have their own ownership checks.
enum LightRecoveryAdmission {
    static func unownedLidNeedsRepair(journalNeedsRecovery: Bool, hasOwnedWatcher: Bool) -> Bool {
        journalNeedsRecovery && !hasOwnedWatcher
    }
}

/// Inert recovery observations/actions for isolated previews and tests only.
/// AppModel discards this environment for every production instance.
@MainActor struct LightRecoveryEnvironment {
    var hardwareAvailable: () -> Bool
    var logoNeedsRecovery: () -> Bool
    var lidNeedsRecovery: () -> Bool
    var repairLid: (Bool) throws -> Void
}
