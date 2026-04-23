import Foundation

/// Explicitly set one or more persistent view-state settings.
///
/// URL form: `md-editor://set-view?<key>=<value>[&<key2>=<value2>...]`
///
/// **Design discipline (per engineering-standards §2.4 + the D11
/// spec):** CLI state setters *assign declared values* — they never
/// toggle. Agents issuing commands cannot reliably observe the
/// current UI state. `on`/`off` are idempotent: `on` twice is safe;
/// `off` when already off is a no-op. **Never** introduce a
/// `?line_numbers=toggle` form — it violates the discipline.
///
/// D11 scope: `line_numbers` key only. Future keys (toolbar,
/// sidebar, etc.) slot into `ViewStateKey.apply` without adding a
/// new command.
///
/// `OpenFileCommand` honors the same keys — see `applyViewState`.
@MainActor
enum SetViewCommand: ExternalCommand {
    static let identifier = ExternalCommandIdentifier.setView

    static func execute(params: [String: String], in workspace: WorkspaceStore) {
        ViewStateApplier.apply(params: params)
    }
}

/// Shared applicator used by both `SetViewCommand` and
/// `OpenFileCommand`. Central table of key → setter.
@MainActor
enum ViewStateApplier {
    /// Iterate every param the caller passed and apply any that match
    /// a known view-state key. Unknown keys are silently ignored so
    /// non-view-state params (`path`, `tab`, `line`, `column`, …) on
    /// the `open` command pass through without warning.
    static func apply(params: [String: String]) {
        for (key, rawValue) in params {
            applyOne(key: key, rawValue: rawValue)
        }
    }

    private static func applyOne(key: String, rawValue: String) {
        switch key {
        case "line_numbers":
            guard let bool = parseOnOff(rawValue) else {
                NSLog("SetView: ignoring \(key)=\(rawValue) (expected on|off)")
                return
            }
            AppSettings.shared.lineNumbersVisible = bool
        default:
            // Not a view-state key. Silent pass-through.
            return
        }
    }

    private static func parseOnOff(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "on", "true", "1": return true
        case "off", "false", "0": return false
        default: return nil
        }
    }
}
