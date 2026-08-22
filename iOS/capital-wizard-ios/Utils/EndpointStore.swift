//
//  EndpointStore.swift
//  capital-wizard-ios
//
//  Which of the two deployed sites this shell points its WebView at.
//

import Foundation

/// The sites the shell can be pointed at.
///
/// Two builds of the same web app are served from two addresses: `main` lands
/// on app.capital-wizard.com, `dev` on dev.capital-wizard.com from a second
/// Pages repository. Everything else about them is identical — same shell, same
/// bridge, same accounts — so the endpoint is a *choice*, not a build flavour,
/// and one binary can be aimed at either.
///
/// Mirrors `DEPLOY_ENDPOINTS` in the web app's src/lib/deployEnvironment.ts and
/// `AppEndpoint` in the Android shell — change one, change all three.
enum AppEndpoint: String, CaseIterable {
    case production
    case development

    /// Trailing slash included: callers concatenate a route straight onto this.
    var baseUrl: String {
        switch self {
        case .production:  return "https://app.capital-wizard.com/"
        case .development: return "https://dev.capital-wizard.com/"
        }
    }

    var host: String? {
        URL(string: baseUrl)?.host
    }
}

/// The chosen endpoint, persisted across launches.
///
/// **Only a channel NAME is ever stored or accepted** — never a URL. The two
/// addresses live here, in the shell, so the web bridge (which any script in
/// the page can reach) can pick between them and nothing else. A stored value
/// that no longer names a channel falls back to production rather than being
/// honoured.
enum EndpointStore {

    /// Deliberately not `WebViewApplicationConst.baseUrlKey` ("applicationBaseUrl"):
    /// that name says URL, and what is kept here is a channel name.
    private static let key = "applicationEndpoint"

    static var current: AppEndpoint {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let endpoint = AppEndpoint(rawValue: raw) else {
            return .production
        }
        return endpoint
    }

    /// The base URL for the current endpoint — what every load starts from.
    static var baseUrl: String { current.baseUrl }

    /// Persists `endpoint`. Returns `true` only if this actually CHANGED it, so
    /// callers can skip the WebView rebuild when a switch is a no-op.
    @discardableResult
    static func set(_ endpoint: AppEndpoint) -> Bool {
        guard endpoint != current else { return false }
        UserDefaults.standard.set(endpoint.rawValue, forKey: key)
        CWLog.shared.log("Endpoint set to \(endpoint.rawValue) (\(endpoint.baseUrl))", category: "WebView")
        return true
    }

    /// The allowlist gate: turns whatever the web sent into a known endpoint, or
    /// nothing. Every value crossing the bridge goes through here.
    static func endpoint(named raw: Any?) -> AppEndpoint? {
        guard let name = raw as? String else { return nil }
        return AppEndpoint(rawValue: name)
    }
}
