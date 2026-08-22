//
//  WebViewApplication.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import WebKit
import UIKit

struct WebViewApplicationConst {
    static let baseUrlKey = "applicationBaseUrl"

    /// The site this shell is currently pointed at — production by default, the
    /// development one when an admin has switched it (see `EndpointStore`).
    /// Computed rather than constant so every caller — the initial load, the
    /// route builder, and both same-host navigation checks — follows the switch
    /// together. A stale one of those would send in-app links out to Safari.
    static var applicationBaseUrl: String { EndpointStore.baseUrl }

    static let contentControllerName = "iosCW"

    /// Shared process pool so all WebViews share cookies and sessions.
    static let sharedProcessPool = WKProcessPool()
}

class WebViewApplication: NSObject, Application {
    var id:       String
    var name:     String
    var tabIcon:  UIImage?
    var bigIcon:  UIImage?
    var tagIndex: Int

    var sideBarPriority:  Priority
    var hasNavigationBar: Bool
    var layout: ApplicationUILayout = [ .all ]

    var controller: ApplicationViewController?
    var rootController: UIViewController?
    
    var appData: ApplicationData
    
    var webViewController: WebViewApplicationController? {
        controller as? WebViewApplicationController
    }
    
    private var isActive   = false
    private var needReload = false
    private var didLogin   = false

    /// True once the app has gone to the background since it was last active.
    /// Lets us ignore transient activations (Control Center, the notification
    /// shade) where the app never actually backgrounded.
    private var didBackgroundSinceActive = false
    /// When the app last entered the background — used for the staleness check.
    private var backgroundedAt: Date?
    
    lazy var webViewCommunication: WebViewCommunication  = WebViewCommunication()
    lazy var windowsService:       WindowsService?       = ServiceManager.shared.getService()
    lazy var applicationService:   ApplicationService?   = ServiceManager.shared.getService()
    lazy var deepLinkService:      DeepLinkService?      = ServiceManager.shared.getService()
    lazy var pushService:          PushService?          = ServiceManager.shared.getService()

    private lazy var onColorChangeHandler: EventCallback = EventCallback(onColorSchemeChanged(_:))
    private lazy var onAppReadyHandler:    EventCallback = EventCallback(onAppReady)
    private lazy var onEndpointChangedHandler: EventCallback = EventCallback(onEndpointChanged)
    private lazy var onDeepLinkHandler:    EventCallback = EventCallback(onDeepLink(_:))
    private lazy var onPushRegistrationHandler: EventCallback<PushRegistration?> = EventCallback(onPushRegistration(_:))
    private lazy var onExternalURLHandler:      EventCallback<Void> = EventCallback(onExternalURL(_:))
    private lazy var onOpenRecordedHandler:     EventCallback<Void> = EventCallback(onOpenRecorded(_:))

    init(appData: ApplicationData, hasNavigationBar: Bool, tagIndex: Int) {
        self.appData            = appData
        self.id                 = appData.id
        self.name               = appData.name
        self.tabIcon            = appData.tabIcon
        self.bigIcon            = appData.bigIcon
        self.hasNavigationBar   = hasNavigationBar
        self.tagIndex           = tagIndex
        self.layout             = appData.layout
        self.sideBarPriority    = appData.sidebarPriority
    }
    
    func awake() {
        let controller          = WebViewApplicationController()
        controller.application = self
        
        self.controller   = controller
        
        webViewController?.contentController = webViewCommunication.contentController
        webViewController?.urlFactory        = self
        webViewController?.delegate          = self
        webViewController?.appType           = appData.type
        webViewController?.id                = appData.id
    }
    
    func start() {
        windowsService?.onColorSchemeChanged += onColorChangeHandler
        webViewCommunication.onAppReady += onAppReadyHandler
        webViewCommunication.onEndpointChanged += onEndpointChangedHandler
        deepLinkService?.onDeepLink += onDeepLinkHandler
        pushService?.onRegistration += onPushRegistrationHandler
        pushService?.onExternalURL += onExternalURLHandler
        pushService?.onOpenRecorded += onOpenRecordedHandler

        // Detect resume-from-background so we can recover a WebView whose
        // web-content process was killed (or whose content was discarded) while
        // the app sat in the background. See onAppDidBecomeActive.
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(onAppDidEnterBackground),
                                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(onAppDidBecomeActive),
                                       name: UIApplication.didBecomeActiveNotification, object: nil)

        CWLog.shared.log("WebView application started (id=\(id))", category: "WebView")
    }

    /// A link arrived while this app instance was alive. If the web bridge is up
    /// we route in place; if it isn't — still on the splash, signed out, or the
    /// WebView not built yet — we leave the path stashed and let the next initial
    /// load consume it, so the link is never lost and never applied twice.
    private func onDeepLink(_ path: String) {
        guard webViewCommunication.isReady else {
            CWLog.shared.log("Deep link \(path) arrived before the bridge was ready — leaving it stashed",
                             category: "DeepLink")
            return
        }
        guard let pending = deepLinkService?.consumePendingPath() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.webViewCommunication.pushNavigate(path: pending) { return }

            // The bridge died between the check and the push — fall back to a
            // full load so the link still lands.
            CWLog.shared.log("Route push failed — falling back to a full load of \(pending)", category: "DeepLink")
            if let url = try? self.getUrl(from: String(pending.dropFirst())) {
                self.webViewController?.reload(with: url)
            }
        }
    }

    /// APNs answered the web app's token request. Forward it over the bridge so
    /// the web side can store it against the signed-in account. A refusal comes
    /// through as `nil` and is forwarded too — the web app is waiting for an
    /// answer, not necessarily a token.
    private func onPushRegistration(_ registration: PushRegistration?) {
        DispatchQueue.main.async { [weak self] in
            self?.webViewCommunication.pushRegistration(
                registration,
                failureReason: self?.pushService?.lastFailureReason
            )
        }
    }

    /// A tapped notification carried an external page. Show it only if the app
    /// is already up; on a cold start the bridge is not ready yet and the page
    /// stays stashed for `onAppReady` below — presenting over a launching app is
    /// what wedged it behind the splash.
    private func onExternalURL(_: Void) {
        guard webViewCommunication.isReady else {
            CWLog.shared.log("External link arrived before the app was up — leaving it stashed",
                             category: "Push")
            return
        }
        if let url = pushService?.consumePendingExternalURL() {
            PushService.presentExternal(url)
        }
    }

    /// A tapped notification carried a click-tracking id. Forward it if the
    /// bridge is live (a warm tap); otherwise leave it stashed — a cold start's
    /// ids are flushed by `onAppReady`, which is also the earliest moment the
    /// web app's session is restored enough to report them.
    private func onOpenRecorded(_: Void) {
        guard webViewCommunication.isReady else {
            CWLog.shared.log("Tap report arrived before the app was up — leaving it stashed",
                             category: "Push")
            return
        }
        flushOpenReports()
    }

    /// Hands the stashed tap ids to the web app. Consuming clears the stash, so
    /// a failed push puts nothing back — dropping a best-effort statistic beats
    /// machinery to retry it.
    private func flushOpenReports() {
        guard let ids = pushService?.consumePendingOpenReports(), !ids.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webViewCommunication.pushOpened(sendIds: ids)
        }
    }

    /// An admin switched the endpoint from inside the web app. The new address
    /// is already persisted; rebuilding the WebView is what moves us onto it —
    /// a plain reload would re-fetch the OLD url and would also keep the
    /// document-start script that told the page which site it was on.
    private func onEndpointChanged() {
        CWLog.shared.log("Endpoint changed — restarting the web layer", category: "WebView")
        DispatchQueue.main.async { [weak self] in
            self?.recreateWebView()
        }
    }

    private func onAppReady() {
        CWLog.shared.log("Web app reported ready — revealing WebView", category: "WebView")

        // The web app is signed in and rendering, so taps stashed through a
        // cold launch can finally be reported.
        flushOpenReports()

        DispatchQueue.main.async { [weak self] in
            self?.webViewController?.revealWebView()

            // The app is now genuinely on screen, so a link stashed during a cold
            // launch is finally safe to present over it.
            if let url = self?.pushService?.consumePendingExternalURL() {
                PushService.presentExternal(url)
            }
        }
    }
    
    func stop() {
        isActive = false
        
        webViewController?.hideWebView()
        if UIDevice.current.userInterfaceIdiom == .phone {
            controller?.dismiss(animated: false)
        }
        
        windowsService?.onColorSchemeChanged -= onColorChangeHandler
        webViewCommunication.onAppReady -= onAppReadyHandler
        webViewCommunication.onEndpointChanged -= onEndpointChangedHandler
        deepLinkService?.onDeepLink -= onDeepLinkHandler
        pushService?.onRegistration -= onPushRegistrationHandler
        pushService?.onExternalURL -= onExternalURLHandler

        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    func pause() {
        isActive = false
    }
    
    func resume(layout: ApplicationUILayout?) {
        isActive = true
        
        reloadWebViewIfNeedded()
    }

    /// Clears all WebKit data (cookies, cache, etc.) from the default data store.
    static func cleareAllData() {
        Task { @MainActor in
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let dataStore = WKWebsiteDataStore.default()
            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
            let cookies = await dataStore.httpCookieStore.allCookies()
            for cookie in cookies {
                await dataStore.httpCookieStore.deleteCookie(cookie)
            }
        }
    }
    
    private func reloadWebViewIfNeedded() {
        guard needReload else { return }
        needReload = false
        recreateWebView()
    }

    @objc private func onAppDidEnterBackground() {
        isActive = false
        didBackgroundSinceActive = true
        backgroundedAt = Date()
        CWLog.shared.log("Entered background", category: "WebView")
    }

    @objc private func onAppDidBecomeActive() {
        isActive = true

        // Ignore transient activations (Control Center / notification shade) —
        // only act on a real return from the background.
        guard didBackgroundSinceActive else { return }
        didBackgroundSinceActive = false

        // A (re)load is already in progress — its preloader is on screen. Don't tear
        // it down here, or the W animation visibly restarts. A load whose web-content
        // process actually dies is still covered by the terminate handler.
        if webViewController?.isShowingSplash == true {
            CWLog.shared.log("Became active while preloader showing — leaving load in progress", category: "WebView")
            return
        }

        let elapsed = backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
        backgroundedAt = nil

        // Nothing to recover if the WebView was never instantiated.
        guard webViewController?.isViewLoaded == true else {
            CWLog.shared.log("Resumed but WebView not instantiated — skipping", category: "WebView")
            return
        }

        // Fast path: WebKit already reported the web-content process dead while we
        // were backgrounded — reload now, no need to probe.
        if needReload {
            needReload = false
            CWLog.shared.log("Renderer terminated while backgrounded — reloading", category: "WebView")
            recreateWebView()
            return
        }

        // Otherwise PING the live web content and reload ONLY if it is unresponsive
        // (dead process) or blank (rendered nothing). A healthy app is left exactly
        // as it was — no needless reload, so the user is never bounced back through
        // the auth screen for an app that was actually fine.
        CWLog.shared.log(String(format: "Resumed after %.0fs — pinging web content", elapsed), category: "WebView")
        webViewController?.pingWebContent { [weak self] healthy in
            guard let self = self else { return }
            if healthy {
                CWLog.shared.log("Health ping OK — WebView left as-is", category: "WebView")
            } else {
                CWLog.shared.log("Health ping failed (unresponsive/blank) — reloading WebView", category: "WebView")
                self.recreateWebView()
            }
        }
    }

    /// Tears down the current (possibly dead/blank) WebView and builds a fresh one
    /// behind the splash/preloader — effectively a full restart of the web layer.
    /// Shared by the terminate handler, the foreground staleness recovery, and the
    /// resume path so they stay consistent.
    private func recreateWebView() {
        CWLog.shared.log("Recreating WebView (fresh load behind preloader)", category: "WebView")
        didLogin = false
        webViewController?.hideWebView()
        webViewCommunication.clearData()
        webViewController?.contentController = webViewCommunication.contentController
        webViewController?.createWkWebView(withPreloader: true)
    }
 
    private func onColorSchemeChanged(_ scheme: ColorScheme) {
        guard webViewCommunication.isReady else {
            return
        }
        webViewController?.updateColorScheme(scheme)
        updateWebViewColorScheme(to: scheme)
    }

    
    /// Runtime native → web push. When the native theme changes while running
    /// (e.g. the ProfilePopover Light/Dark/System control, or a system
    /// appearance flip while following the system), persist the equivalent web
    /// mode and push it into the live WebView so both stay in sync.
    private func updateWebViewColorScheme(to scheme: ColorScheme) {
        guard let windowsService = windowsService else { return }
        // Prefer the saved exact web string when it still maps to the current
        // preference so a `dark-soft` choice isn't flattened to `dark`.
        let mode = windowsService.webModeForCurrentPreference
        windowsService.savedWebTheme = mode
        webViewCommunication.pushTheme(mode: mode, accent: windowsService.savedWebAccent)
    }
}

extension WebViewApplication: UrlFactory {
    func prepareForInitialLoad() async {
        let authService: AuthService? = ServiceManager.shared.getService()
        guard let session = try? await authService?.client.session else { return }
        await MainActor.run {
            // Seed the theme/accent + generic device-store values into
            // localStorage BEFORE the page's pre-paint inline script runs
            // (atDocumentStart), then inject auth.
            webViewCommunication.addThemeSeedScript()
            webViewCommunication.addKvSeedScript()
            webViewCommunication.addAuthScript(accessToken: session.accessToken, refreshToken: session.refreshToken)
        }
    }

    func getInitialUrl() async throws -> URL {
        var stringUrl: String
        stringUrl = WebViewApplicationConst.applicationBaseUrl

        // A link stashed before the WebView existed — a cold start, or one that
        // sat through the sign-in gate — becomes the very first URL we load, so
        // the user lands on it directly with no visible redirect from the root.
        // `consumePendingPath` clears it, so a later reload won't repeat it.
        if let path = deepLinkService?.consumePendingPath() {
            // Both sides carry a slash: the base URL ends with one, the route
            // starts with one.
            stringUrl += String(path.dropFirst())
        } else {
            stringUrl += "\(appData.baseUrl)"
        }

        guard let url = URL(string: stringUrl) else {
            throw WebViewError(message: "Couldn't create url from \(stringUrl)")
        }
        
        CWLog.shared.log("Loading URL: \(url.absoluteString)", category: "WebView")
        return url
    }
    
    private func getUrl(from string: String) throws -> URL {
        let stringUrl: String
        switch appData.type {
        case .web:
            stringUrl = WebViewApplicationConst.applicationBaseUrl + string
        case .iFrameWeb:
            stringUrl  = "\(WebViewApplicationConst.applicationBaseUrl)\(string)"
        case .native:
            throw WebViewError(message: "You can't get url for native application.")
        }
        guard let url = URL(string: stringUrl) else {
            throw WebViewError(message: "Couldn't create url from \(stringUrl)")
        }
        
        return url
    }
}

extension WebViewApplication: WebViewControllerDelegate {
    func onError(_ error: any Error) {
        CWLog.shared.log("Error: \(error)", category: "WebView")
    }
    
    func willStartLoad(wkWebView: WKWebView) {
        webViewCommunication.wkWebView = wkWebView
    }
    
    func onWebViewTerminated() {
        // The WebView's web-content process was killed (commonly under memory
        // pressure while backgrounded). Rebuild immediately if we're in the
        // foreground; otherwise flag it so onAppDidBecomeActive rebuilds it on
        // the next foreground — never reload while still backgrounded, or the
        // load stalls and the splash times out onto a blank WebView.
        CWLog.shared.log("Web content process terminated (isActive=\(isActive))", category: "WebView")
        if isActive, webViewController?.isViewLoaded == true {
            recreateWebView()
        } else {
            CWLog.shared.log("Terminated while backgrounded — deferring reload to next foreground", category: "WebView")
            needReload = true
        }
    }
}

struct WebViewError: Error, ErrorMessage {
    
    var description: String {
        "Error: [webView] \(message)"
    }
    
    var message: String
}

protocol UrlFactory: AnyObject {
    func getInitialUrl() async throws -> URL
    func prepareForInitialLoad() async
}

extension UrlFactory {
    func prepareForInitialLoad() async {}
}
