import Foundation

/// D30 phase 4 — periodic editor-side sweep that releases interest
/// entries whose CC-side session is no longer heartbeating.
///
/// CC-side responsibility: each session writes `heartbeat.json` to
/// its sidecar dir on a configurable cadence (see
/// `scripts/md-editor-heartbeat`). Default 60s.
///
/// Editor-side responsibility: every `sweepInterval` seconds (5min
/// default), iterate every interest on every open tab; if the
/// session's `heartbeat.json` is missing or older than
/// `stalenessTimeoutSec`, release the interest from every tab.
///
/// Disable knob: `UserDefaults.standard.submitStalenessTimeoutSec`
/// (Double). When ≤ 0, the sweep no-ops on every tick.
@MainActor
final class HeartbeatPruner {
    static let shared = HeartbeatPruner()

    /// How often the sweep runs.
    private static let sweepInterval: TimeInterval = 300

    /// Default staleness threshold when `submitStalenessTimeoutSec` is
    /// unset in UserDefaults.
    static let defaultStalenessTimeoutSec: TimeInterval = 300

    /// UserDefaults key Rick or a settings UI sets to tune (or
    /// disable) the prune. 0 or negative ⇒ disable.
    static let stalenessTimeoutKey = "submitStalenessTimeoutSec"

    private var timer: Timer?

    private init() {}

    func start() {
        stop()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.sweepInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Run the prune sweep once. Public so the harness's
    /// `force_staleness_sweep` action and any future settings UI can
    /// trigger it on demand.
    func sweep() {
        let threshold = currentStalenessTimeout()
        guard threshold > 0 else { return }

        let store = WorkspaceStore.shared
        var staleSessions: Set<String> = []
        for doc in store.tabs.documents {
            for interest in doc.interestedSessions {
                if SubmitSidecar.isStale(
                    forSession: interest.sessionID,
                    thresholdSec: threshold) {
                    staleSessions.insert(interest.sessionID)
                }
            }
        }
        for sessionID in staleSessions {
            store.releaseInterest(sessionID: sessionID, scope: .all)
        }
    }

    func currentStalenessTimeout() -> TimeInterval {
        if let stored = UserDefaults.standard.object(
            forKey: Self.stalenessTimeoutKey) as? Double {
            return stored
        }
        return Self.defaultStalenessTimeoutSec
    }
}
