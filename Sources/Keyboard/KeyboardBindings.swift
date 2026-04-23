import AppKit

/// The one and only place where keyboard chords map to command
/// identifiers.
///
/// Engineering standard §2.3: never duplicate this table or inline
/// chord checks in other files. If you need a new shortcut, add a row
/// here and route through `CommandDispatcher`. This keeps
/// externalization (to a data file for cross-OS sharing or user
/// preferences) a 1-hour refactor rather than a codebase treasure
/// hunt.
enum KeyboardBindings {

    struct Chord: Equatable {
        let modifiers: NSEvent.ModifierFlags
        let key: String  // characters-ignoring-modifiers, lowercased
    }

    struct Binding {
        let chord: Chord
        let commandIdentifier: String
    }

    static let all: [Binding] = [
        // Selection-based formatting
        Binding(chord: Chord(modifiers: [.command], key: "b"),
                commandIdentifier: BoldMutation.identifier),
        Binding(chord: Chord(modifiers: [.command], key: "i"),
                commandIdentifier: ItalicMutation.identifier),
        Binding(chord: Chord(modifiers: [.command], key: "e"),
                commandIdentifier: InlineCodeMutation.identifier),
        Binding(chord: Chord(modifiers: [.command], key: "k"),
                commandIdentifier: LinkMutation.identifier),

        // Line-based formatting
        //
        // NOTE on Shift-bearing chords: NSEvent.charactersIgnoringModifiers
        // ignores Command / Option / Control but APPLIES Shift. So
        // Cmd+Shift+7 delivers cim="&" on US layout (not "7"), and
        // Cmd+Shift+8 delivers cim="*" (not "8"). We store the shifted
        // character here. This is US-layout-specific; localized
        // keyboard-shortcut support is a finding for a later
        // deliverable (likely the D5 toolbar or a dedicated i18n pass),
        // tied to the §2.3 "bindings are a declarative table" rule
        // that keeps externalization cheap.
        Binding(chord: Chord(modifiers: [.command, .shift], key: "&"),
                commandIdentifier: NumberedListMutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .shift], key: "*"),
                commandIdentifier: BulletListMutation.identifier),

        Binding(chord: Chord(modifiers: [.command, .option], key: "0"),
                commandIdentifier: BodyMutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .option], key: "1"),
                commandIdentifier: Heading1Mutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .option], key: "2"),
                commandIdentifier: Heading2Mutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .option], key: "3"),
                commandIdentifier: Heading3Mutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .option], key: "4"),
                commandIdentifier: Heading4Mutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .option], key: "5"),
                commandIdentifier: Heading5Mutation.identifier),
        Binding(chord: Chord(modifiers: [.command, .option], key: "6"),
                commandIdentifier: Heading6Mutation.identifier),
    ]

    /// Only compare the modifier flags that semantically affect a
    /// chord. `.deviceIndependentFlagsMask` includes `.capsLock`,
    /// `.function`, `.numericPad`, `.help` — any of those set on a
    /// user's event would break strict-equality matching with a
    /// binding declared only in terms of Command / Shift / etc.
    private static let chordModifierMask: NSEvent.ModifierFlags =
        [.command, .shift, .control, .option]

    /// Look up a binding by event. Returns nil if no mapping.
    static func match(event: NSEvent) -> Binding? {
        let eventMods = event.modifierFlags.intersection(chordModifierMask)
        let eventKey = (event.charactersIgnoringModifiers ?? "").lowercased()
        return all.first { $0.chord.modifiers == eventMods && $0.chord.key == eventKey }
    }
}
