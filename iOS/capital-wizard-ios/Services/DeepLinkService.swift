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
    static let linkHost = AppProduct.current.appHost
    /// The marketing apex, claimed for referral links ONLY. Its association
    /// file allow-lists `/r/*`, so nothing else on that domain reaches us.
    static let referralHost = AppProduct.current.siteHost
    /// Web route a referral code lands on. The register screen reads `ref`.
    static let referralRoute = "/auth/register"
    /// Custom scheme registered in Info.plist (`CFBundleURLSchemes`).
    static let customScheme = AppProduct.current.urlScheme
    /// Custom-scheme host reserved for routing. `auth` belongs to AuthService.
    static let routeHost = "open"

    /// Fired when a link arrives. Subscribers that can act immediately should
    /// call `consumePendingPath()`; ignoring the event leaves the path stashed.
    var onDeepLink: Event<String> = Event()

    /// Fired when the code this device knows about CHANGES.
    ///
    /// Separate from `onDeepLink` because it answers a different question and
    /// has a different subscriber: the sign-up screen, which is already on the
    /// table when a `/r/CODE` link is tapped and must put the code in its box.
    /// A pre-fill read at `viewDidLoad` cannot cover that — the screen is built
    /// once and the code can arrive at any point afterwards.
    var onReferralCode: Event<String> = Event()

    private var pendingPath: String?

    /// The referral code from the last `/r/<CODE>` link, held in its OWN slot.
    ///
    /// Deliberately not read back out of `pendingPath`: that slot is
    /// single-valued, so a `/join/<token>` invite or a tapped notification
    /// arriving afterwards would erase the code — and the sign-up screen needs to
    /// *peek* it without consuming the route the WebView still has to be sent to.
    /// Kept rather than consumed: a person may back out of Create Account and
    /// come back to it.
    private(set) var pendingReferralCode: String?

    /// Whether a route is waiting to be shown.
    var hasPendingPath: Bool { pendingPath != nil }

    /// Accepts `url` if it resolves to an app route. Returns `false` when it is
    /// not ours — the OAuth callback, another host, or a bare root link — so the
    /// caller can pass it on.
    @discardableResult
    func handle(url: URL?) -> Bool {
        guard let url = url, let path = Self.appPath(from: url) else { return false }

        // Recorded alongside the route, not instead of it: the native sign-up
        // screen shows the code, and the web app is still sent to `?ref=` so the
        // onboarding step can redeem it.
        if let code = Self.referralCode(from: url) {
            noteReferral(code)
        }

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

    /// Records the code the person actually submitted on the sign-up screen.
    ///
    /// The field is editable and the pre-fill can be wrong, so what they SEND is
    /// what has to reach the web app — not what arrived. Writes the same
    /// `/auth/register?ref=` route a `/r/` link produces, because the redemption
    /// path downstream is the same one: the WebView is built after sign-in,
    /// loads that route, and the onboarding step redeems the code from it.
    ///
    /// Refuses to overwrite a pending route that is NOT a referral route — an
    /// invite link the person also tapped is a destination, and this is only a
    /// parameter.
    @discardableResult
    func stashReferral(code raw: String) -> Bool {
        guard let code = ReferralIntake.normalized(raw) else { return false }

        noteReferral(code)
        if pendingPath == nil || pendingPath?.hasPrefix(Self.referralRoute) == true {
            pendingPath = "\(Self.referralRoute)?ref=\(code)"
        }
        CWLog.shared.log("Referral code stashed for the web app → \(code)", category: "Referral")
        return true
    }

    /// Records a code and announces it. Announced only when it is NEW: this is
    /// also reached from the sign-up screen handing back what somebody typed, and
    /// an event echoing a value straight back at the field it came from is a
    /// loop waiting for its first bug.
    private func noteReferral(_ code: String) {
        let changed = code != pendingReferralCode
        pendingReferralCode = code
        ReferralIntake.remember(code)
        if changed { onReferralCode.invoke(code) }
    }

    /// The referral code carried by `url`, or `nil`. Host-checked as well as
    /// path-checked, so only the apex we claim for `/r/*` can set one.
    static func referralCode(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "http",
              url.host?.lowercased() == referralHost else { return nil }
        return referralCode(fromPath: url.path)
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
            let host = url.host?.lowercased()
            if host == linkHost {
                return normalized(path: url.path, query: url.query, fragment: url.fragment)
            }
            // The apex is claimed for one thing only, so it is TRANSLATED rather
            // than passed through: `capital-wizard.com/r/STAN-8F2K` is a page on
            // the marketing site, and the app has no such route. It becomes the
            // sign-up screen with the code attached.
            if host == referralHost, let code = referralCode(fromPath: url.path) {
                return "\(referralRoute)?ref=\(code)"
            }
            return nil
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

    /// The code out of `/r/<CODE>`, upper-cased, or `nil` when the path is not
    /// a referral link. The alphabet matches the database's own check
    /// constraint — anything else is not a code we could resolve anyway.
    static func referralCode(fromPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "r" else { return nil }
        let code = parts[1].uppercased()
        guard code.count >= 3, code.count <= 32,
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let first = code.first, first != "-" else { return nil }
        return code
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
