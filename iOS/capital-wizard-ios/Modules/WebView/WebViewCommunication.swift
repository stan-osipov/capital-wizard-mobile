//
//  WebViewCommunication.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//
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
    
    private var didFinalizeLoad: Bool = false
    
    var isReady: Bool {
        didFinalizeLoad
    }
    
    override init() {
        contentController = WKUserContentController()

        super.init()

        contentController.add(self, name: WebViewApplicationConst.contentControllerName)
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
            guard let dict = message.body as? [String: Any] else {
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
            case .auth:
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

        CWLog.shared.log("Bridge system event: \(eventName)", category: "Bridge")

        if eventName == "api-ready" {
            finilizeLoad()
        }

        if eventName == "app-ready" {
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
