// D18 phase 2 — base URL configuration for the PortableMind connector.
//
// Default = prod (`https://www.dsiloed.com/api/v1`) per memory
// `harmoniq_mcp_points_at_prod.md`. Override via UserDefaults key
// `PortableMindBaseURL` for development pointing at localhost or
// staging:
//
//   defaults write ai.portablemind.md-editor PortableMindBaseURL \
//     "http://localhost:3000/api/v1"
//
// During D18 development, point at localhost to avoid touching prod
// data; flip back to prod for the final phase-6 smoke before COMPLETE.

import Foundation

enum PortableMindEnvironment {
    static let userDefaultsKey = "PortableMindBaseURL"
    static let defaultBaseURL = URL(string: "https://www.dsiloed.com/api/v1")!

    /// Base URL for Harmoniq REST. Reads UserDefaults at access time
    /// so flipping environments doesn't require a rebuild.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: userDefaultsKey),
           let url = URL(string: override) {
            return url
        }
        return defaultBaseURL
    }
}
