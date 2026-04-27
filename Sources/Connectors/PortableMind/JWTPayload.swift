// D18 phase 3 — minimal JWT payload reader. Used to extract
// `tenant_enterprise_identifier` so we can populate the `X-Tenant-ID`
// header on every request.
//
// We do NOT verify the signature here. The server is the one that
// must validate the JWT. We just need to read the public payload to
// know which tenant the token belongs to.

import Foundation

enum JWTPayload {
    /// Returns `tenant_enterprise_identifier` from the payload of the
    /// given JWT, or nil if the token is malformed or doesn't carry
    /// that claim. Bearer prefix tolerated.
    static func tenantEnterpriseIdentifier(from token: String) -> String? {
        let cleaned = token.hasPrefix("Bearer ")
            ? String(token.dropFirst("Bearer ".count))
            : token
        let segments = cleaned.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payloadSegment = String(segments[1])

        // JWT uses base64url (URL-safe) without padding. Convert to
        // standard base64 with padding before decoding.
        var base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return nil }
        return json["tenant_enterprise_identifier"] as? String
    }
}
