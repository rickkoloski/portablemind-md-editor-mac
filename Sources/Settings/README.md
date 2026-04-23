# Settings (stub — D2)

Purpose: the settings schema — what the user can configure (theme, font, toolbar visibility, keyboard profile). Same schema across mac/Windows/Linux per `docs/stack-alternatives.md` architecture lesson #8.

Status: Stub only. No Swift source at D2.

Storage constraint: `UserDefaults` or a small JSON file. No Core Data / SwiftData per `docs/stack-alternatives.md` §"Explicitly not using."

Expected deliverable: paired with the first user-configurable feature — likely D5 (toolbar show/hide state) or a dedicated Preferences window further out.
