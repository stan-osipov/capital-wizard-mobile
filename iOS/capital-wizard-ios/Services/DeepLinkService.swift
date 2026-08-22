//
//  DeepLinkService.swift
//  capital-wizard-ios
//

import Foundation

/// Turns an inbound link into a web-app route and holds it until the WebView is
/// in a position to show it.
///
/// Two ways in:
///   * a **universal link** — `https://app.capital-wizard.com/<path>` — which iOS
///     hands us because the domain's `apple-app-site-association` claims it. This
///     is the path real invite links take.
///   * the **custom scheme** — `capital-wizard-ios://open?path=/join/abc` — a
///     fallback for contexts where universal links don't fire (and a hedge while
///     the association file's hosting is being verified). The OAuth callback uses
///     the same scheme under the `auth` host, so the two never collide.
///
/// A link can land long before we can act on it: the user may be signed out, or
/// the app may be cold-starting with no WebView yet. So the path is *stashed*
/// rather than delivered, and whoever becomes ready first consumes it —
/// `WebViewApplication.getInitialUrl()` on a cold start, or the `onDeepLink`
/// subscriber when the WebView is already live.
class DeepLinkService: Service {

    /// Host claimed by the associated-domains entitlement.
    static let linkHost = "app.capital-wizard.com"
    /// Custom scheme registered in Info.plist (`CFBundleURLSchemes`).
    static let customScheme = "capital-wizard-ios"
    /// Custom-scheme host reserved for routing. `auth` belongs to AuthService.
    static let routeHost = "open"

    /// Fired when a link arrives. Subscribers that can act immediately should
    /// call `consumePendingPath()`; ignoring the event leaves the path stashed.
    var onDeepLink: Event<String> = Event()

    private var pendingPath: String?

    /// Whether a route is waiting to be shown.
    var hasPendingPath: Bool { pendingPath != nil }

    /// Accepts `url` if it resolves to an app route. Returns `false` when it is
    /// not ours — the OAuth callback, another host, or a bare root link — so the
    /// caller can pass it on.
    @discardableResult
    func handle(url: URL?) -> Bool {
        guard let url = url, let path = Self.appPath(from: url) else { return false }

        CWLog.shared.log("Deep link received → \(path)", category: "DeepLink")
        pendingPath = path
        onDeepLink.invoke(path)
        return true
    }

    /// Accepts a route that arrived without a URL around it — today, the `route`
    /// field of a tapped push notification. Same stash-and-announce behaviour as
    /// `handle(url:)`, and the same validation: a value carrying its own scheme
    /// or host is refused, so a notification payload can't point the WebView off
    /// our origin.
    @discardableResult
    func handle(routePath raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              components.scheme == nil, components.host == nil,
              let path = Self.normalized(path: components.path,
                                         query: components.query,
                                         fragment: components.fragment) else {
            return false
        }

        CWLog.shared.log("Route received → \(path)", category: "DeepLink")
        pendingPath = path
        onDeepLink.invoke(path)
        return true
    }

    /// Returns the stashed route and clears it, so a link is only ever applied
    /// once — a later reload must not silently re-navigate the user.
    func consumePendingPath() -> String? {
        guard let path = pendingPath else { return nil }
        pendingPath = nil
        CWLog.shared.log("Deep link consumed → \(path)", category: "DeepLink")
        return path
    }

    // MARK: - URL → route

    /// Maps a supported URL onto a root-relative web-app route, or `nil` when the
    /// URL isn't one we route.
    static func appPath(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()

        if scheme == "https" || scheme == "http" {
            guard url.host?.lowercased() == linkHost else { return nil }
            return normalized(path: url.path, query: url.query, fragment: url.fragment)
        }

        if scheme == customScheme {
            // `capital-wizard-ios://auth/callback` is the OAuth leg — not ours.
            guard url.host?.lowercased() == routeHost,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let raw = components.queryItems?.first(where: { $0.name == "path" })?.value,
                  let inner = URLComponents(string: raw) else {
                return nil
            }
            // Reject anything carrying its own scheme or host: `path` must be a
            // route on our own origin, never a way to point the WebView elsewhere.
            guard inner.scheme == nil, inner.host == nil else { return nil }
            return normalized(path: inner.path, query: inner.query, fragment: inner.fragment)
        }

        return nil
    }

    /// Validates and reassembles a route. Rejects anything not rooted at `/`, and
    /// `//host` (protocol-relative) which would otherwise escape our origin. A
    /// bare `/` returns `nil`: the app already opens there, so there is nothing
    /// to restore.
    private static func normalized(path: String, query: String?, fragment: String?) -> String? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), path != "/" else { return nil }

        var route = path
        if let query = query, !query.isEmpty { route += "?\(query)" }
        if let fragment = fragment, !fragment.isEmpty { route += "#\(fragment)" }
        return route
    }
}
