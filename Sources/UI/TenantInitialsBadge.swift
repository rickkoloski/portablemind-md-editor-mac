// D18 phase 4 — small pill badge surfaced next to a sidebar row when
// the row's tenant differs from the authenticated user's tenant.
// Mirrors `harmoniq-frontend/src/components/shared/TenantInitialsBadge.tsx`
// for visual continuity across the PortableMind ecosystem.
//
// Initials algorithm matches the web component:
//   single-word tenant_name → first letter, uppercase
//   multi-word tenant_name → first letters of first two words, uppercase
//
// Colors (hex):
//   bg #FCE4EC, fg #E5007E

import SwiftUI

struct TenantInitialsBadge: View {
    let tenant: TenantInfo

    var body: some View {
        Text(Self.initials(from: tenant.name))
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Self.foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Self.background)
            )
            .help(tenant.name)
            .accessibilityLabel("shared from \(tenant.name)")
            .accessibilityIdentifier(
                "md-editor.sidebar.tenant-badge.\(tenant.enterpriseIdentifier)")
    }

    static let background = Color(red: 0xFC / 255.0,
                                  green: 0xE4 / 255.0,
                                  blue: 0xEC / 255.0)
    static let foreground = Color(red: 0xE5 / 255.0,
                                  green: 0x00 / 255.0,
                                  blue: 0x7E / 255.0)

    /// Initials algorithm — match the harmoniq-frontend version.
    /// "EpicDX" → "E"; "Rock Cut Brewing Company" → "RC";
    /// "Istonish Prod Support" → "IP".
    static func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        if words.isEmpty { return "?" }
        if words.count == 1 {
            return String(words[0].prefix(1)).uppercased()
        }
        let first = words[0].prefix(1)
        let second = words[1].prefix(1)
        return (String(first) + String(second)).uppercased()
    }
}
