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
    static let applicationBaseUrl    = "https://capital-wizard.com/"
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

    private lazy var onColorChangeHandler: EventCallback = EventCallback(onColorSchemeChanged(_:))
    private lazy var onAppReadyHandler:    EventCallback = EventCallback(onAppReady)

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

    private func onAppReady() {
        CWLog.shared.log("Web app reported ready — revealing WebView", category: "WebView")
        DispatchQueue.main.async { [weak self] in
            self?.webViewController?.revealWebView()
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
        stringUrl += "\(appData.baseUrl)"
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
