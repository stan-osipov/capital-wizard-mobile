//
//  WebViewCommunication.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//
import UIKit
import WebKit

struct WebApiError: Error, ErrorMessage {
    var message: String
    
    var description: String {
        "Error: [webApiError] \(message)"
    }
}

class WebViewCommunication: NSObject {
    var contentController: WKUserContentController
    var onAppReady: Event<Void> = Event()
    var onLoaderReady: Event<Void> = Event()
    /// Fires only when a `set-endpoint` actually MOVED the shell to the other
    /// site; the owning application answers by restarting the web layer.
    var onEndpointChanged: Event<Void> = Event()

    weak var wkWebView: WKWebView?

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    
    private var webView: WKWebView {
        get throws {
            guard let wkWebView = wkWebView else {
                throw WebApiError(message: "WkWebView is nil so we can't call api in it.")
            }
            return wkWebView
        }
    }
    
    private let buttonFeedback = UIImpactFeedbackGenerator(style: .light)
    private let refreshFeedback = UIImpactFeedbackGenerator(style: .medium)
    // A scrub tick fires tens of times during one drag along a chart, so it has
    // to be the faintest thing the phone can produce and still be felt. The
    // selection generator — the obvious choice, and what this used to be — is
    // tuned for a picker wheel turning a few times a second; at a drag's rate
    // it stops reading as a count and starts reading as the phone buzzing in
    // the hand. A `.soft` impact at a FRACTION of full strength is the same tap
    // with the weight taken out of it, which is the one knob `UISelection-
    // FeedbackGenerator` does not offer. Mirrors Android's SEGMENT_FREQUENT_TICK.
    private let tickFeedback = UIImpactFeedbackGenerator(style: .soft)
    /// 0…1. Low enough to read as texture under a moving finger rather than as
    /// a knock; above ~0.5 it is an impact again.
    private let tickIntensity: CGFloat = 0.3

    private var didFinalizeLoad: Bool = false
    
    var isReady: Bool {
        didFinalizeLoad
    }
    
    override init() {
        contentController = WKUserContentController()

        super.init()

        contentController.add(self, name: WebViewApplicationConst.contentControllerName)

        // Tell the web app every time we come back to the foreground. It cannot
        // rely on visibilitychange for this (see WebApicForegroundCall), and a
        // screen showing an OS-owned setting is stale the moment the user walks
        // into Settings to change it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notifyForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // A statement the app itself was handed (SceneDelegate.takeSharedFile).
        // Its own signal rather than a lean on `didBecomeActive`: opening a
        // document from an app that is already frontmost moves the app through
        // no lifecycle state at all, and the read is asynchronous, so the file
        // can land in the inbox well after any activation notification.
        //
        // Guarded like `pushSharedImages` below — the inbox is not built into
        // the Coding Lab target, which has no import wizard to deliver to.
        #if !CODING_LAB
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notifySharedFile),
            name: SharedImageInbox.didReceive,
            object: nil
        )
        #endif
    }

    @objc private func notifyForeground() {
        Task { @MainActor in await StoreService.shared.reconcile() }
        pushForeground()
        pushSharedImages()
        #if !CODING_LAB
        // Any Apple Pay payment the intent could not send — no network at the
        // till, or a Keychain it could not read while the phone was locked —
        // goes out now. Coming to the foreground is the one moment both of
        // those are reliably true again, which is why this is the drain that
        // actually rescues a held payment rather than the one in the intent.
        // Cheap when there is nothing queued: one directory listing.
        Task { await ApplePayPoster.drain() }
        #endif
    }

    #if !CODING_LAB
    @objc private func notifySharedFile() {
        DispatchQueue.main.async { [weak self] in self?.pushSharedImages() }
    }
    #endif

    /// Best-effort runtime native → web foreground ping via
    /// `window.__capital_wizard.foreground({…})`. No-op before the first load
    /// finishes — a page that has not rendered yet has nothing stale to refresh.
    func pushForeground() {
        guard didFinalizeLoad, let wkWebView = wkWebView else { return }
        guard let js = try? WebApicForegroundCall().apiCall else { return }
        DispatchQueue.main.async {
            wkWebView.evaluateJavaScript(js)
        }
    }

    private var deliveringShare = false

    func pushSharedImages() {
        #if !CODING_LAB
        guard didFinalizeLoad, !deliveringShare, let view = wkWebView,
              view.url?.host == URL(string: EndpointStore.baseUrl)?.host else { return }
        deliveringShare = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak view] in
            let payload = try? SharedImageInbox.next()
            DispatchQueue.main.async {
                guard let self else { return }
                self.deliveringShare = false
                guard let payload, let view, self.wkWebView === view,
                      view.url?.host == URL(string: EndpointStore.baseUrl)?.host else { return }
                view.evaluateJavaScript("window.__capital_wizard?.sharedImages?.(\(payload));")
            }
        }
        #endif
    }

    func clearData() {
        didFinalizeLoad = false

        contentController.removeScriptMessageHandler(forName: WebViewApplicationConst.contentControllerName)
        contentController = WKUserContentController()
        contentController.add(self, name: WebViewApplicationConst.contentControllerName)
    }

    func addAuthScript(accessToken: String, refreshToken: String) {
        let authCall = WebApicAuthCall(authToken: accessToken, refreshToken: refreshToken)
        guard let js = try? authCall.apiCall else { return }
        contentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    /// Seeds `localStorage['cw-theme']` / `localStorage['cw-accent']` from the
    /// saved device-local values BEFORE the page's own pre-paint inline script
    /// runs, so the web app boots in the user's chosen theme/accent. Injects
    /// nothing when nothing has been saved yet (web keeps its own auto/amber
    /// default). Runs at `.atDocumentStart` for the same reason.
    func addThemeSeedScript() {
        guard let js = Self.themeSeedJS(mode: windowsService?.savedWebTheme,
                                        accent: windowsService?.savedWebAccent) else { return }
        contentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Builds the localStorage-seeding JS, escaping the values via JSON so a
    /// hostile/garbage saved value can never break out of the string literal.
    /// Returns `nil` when there is nothing to seed.
    static func themeSeedJS(mode: String?, accent: String?) -> String? {
        var lines: [String] = []
        if let mode = mode, let lit = jsStringLiteral(mode) {
            lines.append("try { localStorage.setItem('cw-theme', \(lit)); } catch (e) {}")
        }
        if let accent = accent, let lit = jsStringLiteral(accent) {
            lines.append("try { localStorage.setItem('cw-accent', \(lit)); } catch (e) {}")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Seeds every saved generic KV pair into `localStorage` BEFORE the page's
    /// pre-paint script runs (same `.atDocumentStart` timing/rationale as
    /// `addThemeSeedScript`), so the web `deviceStore` reads them back
    /// transparently. Injects nothing when the store is empty.
    func addKvSeedScript() {
        guard let js = Self.kvSeedJS(DeviceKVStore.all()) else { return }
        contentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Builds the `localStorage`-seeding JS for the generic KV store. Both key
    /// and value are escaped via `jsStringLiteral`, so arbitrary saved content
    /// can never break out of the string literal. Returns `nil` when empty.
    static func kvSeedJS(_ pairs: [String: String]) -> String? {
        let lines: [String] = pairs.compactMap { key, value in
            guard let k = jsStringLiteral(key), let v = jsStringLiteral(value) else { return nil }
            return "try { localStorage.setItem(\(k), \(v)); } catch (e) {}"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Produces a safe, double-quoted JS string literal for an arbitrary value
    /// by round-tripping it through `JSONSerialization` (JSON strings are valid
    /// JS string literals). Returns `nil` if serialization fails.
    private static func jsStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        // `["amber"]` → `"amber"`
        return String(json.dropFirst().dropLast())
    }

    /// Best-effort runtime native → web push: applies `mode`/`accent` in the
    /// live web app via `window.__capital_wizard.theme({…})`. No-op when the
    /// WebView isn't ready/live.
    func pushTheme(mode: String, accent: String?) {
        guard didFinalizeLoad, let wkWebView = wkWebView else { return }
        let call = WebApicThemeCall(mode: mode, accent: accent)
        guard let js = try? call.apiCall else { return }
        wkWebView.evaluateJavaScript(js)
    }
    
    /// Best-effort runtime native → web route push: opens `path` in the live web
    /// app via `window.__capital_wizard.navigate({…})`. Returns `false` when the
    /// WebView isn't ready, so the caller can leave the link stashed for the next
    /// initial load instead of dropping it.
    @discardableResult
    func pushNavigate(path: String) -> Bool {
        guard didFinalizeLoad, let wkWebView = wkWebView else { return false }
        let call = WebApicNavigateCall(path: path)
        guard let js = try? call.apiCall else { return false }
        wkWebView.evaluateJavaScript(js)
        return true
    }

    /// Best-effort runtime native → web push registration: hands the APNs token
    /// (or a refusal) to the live web app via `window.__capital_wizard.push({…})`.
    /// No-op when the WebView isn't ready — the web side asks again on the next
    /// sign-in, so nothing is lost.
    func pushRegistration(_ registration: PushRegistration?, failureReason: String? = nil) {
        guard didFinalizeLoad, let wkWebView = wkWebView else { return }
        let call = WebApicPushCall(registration: registration, failureReason: failureReason)
        guard let js = try? call.apiCall else { return }
        wkWebView.evaluateJavaScript(js)
    }

    /// Best-effort runtime native → web tap report: hands the tapped
    /// notifications' send ids to the live web app via
    /// `window.__capital_wizard.pushOpened({…})`, which counts them through its
    /// authenticated RPC. Returns `false` when the WebView isn't ready, so the
    /// caller can leave the ids stashed for the app-ready flush instead of
    /// losing them.
    @discardableResult
    func pushOpened(sendIds: [String]) -> Bool {
        guard !sendIds.isEmpty else { return true }
        guard didFinalizeLoad, let wkWebView = wkWebView else { return false }
        let call = WebApicPushOpenedCall(sendIds: sendIds)
        guard let js = try? call.apiCall else { return false }
        wkWebView.evaluateJavaScript(js)
        return true
    }

    /// Best-effort runtime native → web push status: hands the OS notification
    /// permission to the live web app via `window.__capital_wizard.pushStatus({…})`.
    /// No-op when the WebView isn't ready — the web side asks again whenever the
    /// screen that cares about it opens.
    func pushStatus(permission: String) {
        guard didFinalizeLoad, let wkWebView = wkWebView else { return }
        let call = WebApicPushStatusCall(permission: permission)
        guard let js = try? call.apiCall else { return }
        wkWebView.evaluateJavaScript(js)
    }

    private func finilizeLoad() {
        Task(priority: .high) {
            didFinalizeLoad = true
            let authService: AuthService? = ServiceManager.shared.getService()
            do {
                guard let session = try await authService?.client.session else {
                    return
                }
                let webApiCall = WebApicAuthCall(authToken: session.accessToken, refreshToken: session.refreshToken)
                try await MainActor.run {
                    try send(data: webApiCall)
                }
            } catch let error {
                print(error)
            }
        }
    }


    private func send(data: WebApiCall) throws {
        try webView.evaluateJavaScript(try data.apiCall)
    }
}


extension WebViewCommunication: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == WebViewApplicationConst.contentControllerName {
            guard message.frameInfo.isMainFrame, let dict = message.body as? [String: Any] else {
                return
            }
            
            guard let typeString = dict["type"] as? String, let type = WebApiCallType(rawValue: typeString) else {
                return
            }
            
            switch type {
            case .system:
                parseSystemResponse(dict)
            case .theme:
                parseThemeResponse(dict)
            case .kv:
                parseKvResponse(dict)
            case .auth, .navigate, .push, .pushOpened, .pushStatus, .foreground:
                // Native → web only; the web app never posts these back.
                break
            }
        }
    }

    /// Handles `{ type: "theme", mode, accent }` posted by the web app when the
    /// user changes theme/accent. Persists both verbatim and mirrors the mode
    /// onto the native `ThemePreference` so auth/splash chrome matches.
    private func parseThemeResponse(_ dict: Dictionary<String, Any>) {
        guard let mode = dict["mode"] as? String, !mode.isEmpty else { return }
        let accent = dict["accent"] as? String
        DispatchQueue.main.async { [weak self] in
            self?.windowsService?.applyWebTheme(mode: mode, accent: accent)
        }
    }

    /// Handles `{ type: "kv", action: "set"|"remove", key, value }` posted by the
    /// web's `deviceStore`. Persists the pair verbatim so it can be re-seeded on
    /// the next launch. `key` is the full `localStorage` key; `DeviceKVStore`
    /// guards that it is within the `cw-kv:` namespace.
    private func parseKvResponse(_ dict: Dictionary<String, Any>) {
        guard let key = dict["key"] as? String, !key.isEmpty else { return }
        let action = dict["action"] as? String ?? "set"
        switch action {
        case "remove":
            DeviceKVStore.remove(key: key)
        default:
            guard let value = dict["value"] as? String else { return }
            DeviceKVStore.set(key: key, value: value)
        }
    }

    private func parseSystemResponse(_ dict: Dictionary<String, Any>) {
        guard let eventName = dict["eventName"] as? String else {
            return
        }

        // Button preference is applied by the web; refresh always reaches here.
        // Run UIKit feedback on the main thread and only for our current page.
        if eventName == "haptic" {
            guard let kind = dict["kind"] as? String,
                  kind == "button" || kind == "refresh" || kind == "tick" else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.wkWebView,
                      view.url?.host == URL(string: EndpointStore.baseUrl)?.host else { return }
                if kind == "tick" {
                    self.tickFeedback.impactOccurred(intensity: self.tickIntensity)
                } else {
                    (kind == "refresh" ? self.refreshFeedback : self.buttonFeedback).impactOccurred()
                }
            }
            return
        }

        CWLog.shared.log("Bridge system event: \(eventName)", category: "Bridge")

        if ["store-products", "store-purchase", "store-restore", "store-manage"].contains(eventName) {
            Task { @MainActor [weak self] in
                guard let self, let view = self.wkWebView,
                      view.url?.host == URL(string: EndpointStore.baseUrl)?.host else { return }
                let reply = await StoreService.shared.handle(dict)
                guard let reply, self.wkWebView === view,
                      view.url?.host == URL(string: EndpointStore.baseUrl)?.host,
                      let data = try? JSONSerialization.data(withJSONObject: reply.payload),
                      let json = String(data: data, encoding: .utf8) else { return }
                view.evaluateJavaScript("window.__capital_wizard?.\(reply.handler)?.(\(json));", completionHandler: nil)
            }
            return
        }

        if eventName == "api-ready" {
            finilizeLoad()
        }

        // WHERE THIS PHONE LOGS APPLE PAY PAYMENTS. The App Intent runs with
        // nobody watching — on a lock screen, seconds after a tap at a till —
        // so it cannot ask which space the payment belongs to and cannot reach
        // the web app to find out: on a cold intent launch there is no WebView
        // and never will be one. So the settings screen TELLS the shell, once,
        // and the shell keeps the answer. `applePayNative.ts` is the other half
        // of this contract; `ApplePayConfigStore.apply` validates the payload.
        //
        // The host check is the same one every branch here makes, and it earns
        // its keep more than most: this message decides where a person's
        // payments are written, so it is taken only from our own page.
        if eventName == "apple-pay-configure" {
            #if !CODING_LAB
            guard wkWebView?.url?.host == URL(string: EndpointStore.baseUrl)?.host else { return }
            switch ApplePayConfigStore.apply(dict) {
            case .configured(_, let typeCount):
                // No space name and no ids in the log — it is copied into
                // support messages. The count is what answers "did the category
                // list actually arrive?", which is the one question this log is
                // ever asked.
                CWLog.shared.log("Apple Pay: configured with \(typeCount) categor\(typeCount == 1 ? "y" : "ies")", category: "ApplePay")
                // Anything captured while the phone was unconfigured — or while
                // it was offline — goes out now. The web app is on screen, so
                // the device is unlocked and the Keychain is readable, which is
                // the one moment a held payment is certain to be sendable.
                Task { await ApplePayPoster.drain() }
            case .cleared:
                CWLog.shared.log("Apple Pay: logging turned off", category: "ApplePay")
            case .ignored:
                CWLog.shared.log("Apple Pay: ignored a configure message that did not parse", category: "ApplePay")
            }
            #endif
        }

        // A painted web loader can take over before services finish initializing.
        if eventName == "loader-ready" {
            onLoaderReady.invoke(())
        }

        if eventName == "shared-images-saved" {
            #if !CODING_LAB
            guard let id = dict["id"] as? String,
                  wkWebView?.url?.host == URL(string: EndpointStore.baseUrl)?.host else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                try? SharedImageInbox.acknowledge(id)
                DispatchQueue.main.async { self?.pushSharedImages() }
            }
            #endif
            return
        }

        if eventName == "app-ready" {
            pushSharedImages()
            Task { @MainActor in await StoreService.shared.reconcile() }
            onAppReady.invoke(())
        }

        if eventName == "logout" {
            Task {
                let authService: AuthService? = ServiceManager.shared.getService()
                try? await authService?.signOut()
            }
        }

        if eventName == "request-logs" {
            sendLogs(requestId: dict["requestId"])
        }

        if eventName == "open-external-url" {
            openExternalUrl(dict["url"])
        }

        if eventName == "request-push-token" {
            let pushService: PushService? = ServiceManager.shared.getService()
            pushService?.requestRegistration()
        }

        // Reads the permission WITHOUT prompting — this is the settings screen
        // asking what the state is, not the app asking for access.
        if eventName == "request-push-status" {
            let pushService: PushService? = ServiceManager.shared.getService()
            pushService?.readPermission { [weak self] permission in
                self?.pushStatus(permission: permission)
            }
        }

        if eventName == "open-push-settings" {
            let pushService: PushService? = ServiceManager.shared.getService()
            pushService?.openSystemSettings()
        }

        if eventName == "set-endpoint" {
            setEndpoint(dict["endpoint"])
        }
    }

    /// Handles `{ type: "system", eventName: "set-endpoint", endpoint }` — an
    /// admin re-pointing the app at the production or the development site.
    ///
    /// What arrives is a channel NAME, and it is resolved through
    /// `EndpointStore`'s allowlist; the two addresses never cross the bridge.
    /// That is what makes this safe to expose on `window`: the worst a hostile
    /// script in the page can do is send the user to the other site of ours.
    private func setEndpoint(_ raw: Any?) {
        guard let endpoint = EndpointStore.endpoint(named: raw) else {
            CWLog.shared.log("Ignoring set-endpoint for an unknown endpoint", category: "Bridge")
            return
        }
        DispatchQueue.main.async {
            guard EndpointStore.set(endpoint) else { return }
            self.onEndpointChanged.invoke(())
        }
    }

    /// Opens a web-requested URL in the system (native map app, Safari, …) via
    /// `UIApplication.open`. Restricted to http/https so the web bridge can never
    /// trigger arbitrary custom-scheme deep links. Backs the address → "open in
    /// maps" chooser, whose `window.open` the WebView would otherwise swallow.
    private func openExternalUrl(_ raw: Any?) {
        guard let urlString = raw as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    /// Answers a web `request-logs` event by serializing the recent native log
    /// lines and calling `window.__capital_wizard.logs({...})` in the WebView.
    private func sendLogs(requestId: Any?) {
        let lines = CWLog.shared.snapshot()
        CWLog.shared.log("Returning \(lines.count) native log line(s) to web", category: "Bridge")
        var payload: [String: Any] = ["platform": "ios", "lines": lines]
        if let requestId = requestId { payload["requestId"] = requestId }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.__capital_wizard && window.__capital_wizard.logs && window.__capital_wizard.logs(\(json));"

        DispatchQueue.main.async { [weak self] in
            self?.wkWebView?.evaluateJavaScript(js)
        }
    }
}
