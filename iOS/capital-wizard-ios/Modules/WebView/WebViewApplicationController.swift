//
//  WebViewApplicationController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import WebKit

protocol WebViewControllerDelegate: AnyObject {
    func onError(_ error: Error)
    func onWebViewTerminated()
    func willStartLoad(wkWebView: WKWebView)
}

class WebViewApplicationController: ApplicationViewController {

    private var wkWebView: WKWebView?

    var onLoadedEvent: Event<Void> = Event()

    var webViewDidLoaded: Bool   = false
    var appType: ApplicationType = .web
    var id:      String          = ""

    var contentController: WKUserContentController?
    weak var urlFactory:   UrlFactory?
    weak var delegate:     WebViewControllerDelegate?

    private var splashView:     UIView?
    private var readyTimeoutWork: DispatchWorkItem?

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var isDarkMode: Bool {
        windowsService?.colorScheme.isDarkMode ?? false
    }

    /// True while the splash/preloader is on screen — i.e. a (re)load is in progress
    /// and has not been revealed yet. Recovery checks this so it never tears down a
    /// preloader that is already running (which would restart the W animation).
    var isShowingSplash: Bool { splashView != nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        createWkWebView(withPreloader: true)
    }

    func createWkWebView(withPreloader hasPreloader: Bool = false) {
        guard let contentController = contentController else {
            return
        }
        CWLog.shared.log("Creating WKWebView (preloader=\(hasPreloader))", category: "WebView")
        SplashAnimationView.postStatus("Creating browser…")

        let config = WKWebViewConfiguration()
        config.processPool = WebViewApplicationConst.sharedProcessPool
        config.userContentController = contentController
        config.userContentController.addUserScript(self.getNativeAppScript())
        config.userContentController.addUserScript(self.getZoomDisableScript())

        let wkWebView = WKWebView(frame: self.view.frame, configuration: config)
        wkWebView.uiDelegate = self
        wkWebView.navigationDelegate = self
        wkWebView.allowsBackForwardNavigationGestures = true

        if #available(iOS 16.4, *) {
            wkWebView.isInspectable = true
        }

        delegate?.willStartLoad(wkWebView: wkWebView)

        let scheme = windowsService?.colorScheme ?? .light

        // The web app is a fixed app shell — all scrolling happens inside its own
        // containers. Lock the WebView's document scroll view completely: no user
        // scrolling, no rubber-band bounce, no pull-to-refresh, no zoom. The web
        // app offers a "Reload app" action in its side menu instead.
        wkWebView.scrollView.isScrollEnabled          = false
        wkWebView.scrollView.bounces                  = false
        wkWebView.scrollView.alwaysBounceVertical     = false
        wkWebView.scrollView.alwaysBounceHorizontal   = false
        wkWebView.scrollView.scrollsToTop             = false
        wkWebView.scrollView.minimumZoomScale         = 1.0
        wkWebView.scrollView.maximumZoomScale         = 1.0

        setupView(for: wkWebView, colorScheme: scheme)

        if hasPreloader {
            showSplash(scheme: scheme)
        }

        self.wkWebView = wkWebView
        removeInputAccessoryView()
        initialLoad()
    }

    // MARK: - Splash

    private func showSplash(scheme: ColorScheme) {
        splashView?.removeFromSuperview()

        let splash = SplashAnimationView()
        splash.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splash)

        NSLayoutConstraint.activate([
            splash.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splash.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splash.topAnchor.constraint(equalTo: view.topAnchor),
            splash.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        splashView = splash

        // Timeout fallback
        let timeout = DispatchWorkItem { [weak self] in
            CWLog.shared.log("Preloader timeout (15s) reached — revealing WebView anyway", category: "WebView")
            SplashAnimationView.postStatus("Timeout — revealing app")
            self?.revealWebView()
        }
        readyTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    }

    func revealWebView() {
        readyTimeoutWork?.cancel()
        readyTimeoutWork = nil

        guard let splash = splashView as? SplashAnimationView else {
            splashView?.removeFromSuperview()
            splashView = nil
            return
        }

        // Ensure at least 1.5s of animation plays before dismissing
        let elapsed = CACurrentMediaTime() - splash.createdAt
        let minDisplay: CFTimeInterval = 1.5
        let remaining = max(0, minDisplay - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self = self, self.splashView != nil else { return }

            // Prepare WebView for reveal: start slightly scaled down and transparent
            if let webView = self.wkWebView {
                webView.alpha = 0
                webView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            }

            // Animations keep running during fade — no freeze frame
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                splash.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                splash.alpha = 0
            }, completion: { _ in
                splash.stopAllAnimations()
                splash.removeFromSuperview()
                self.splashView = nil
            })

            UIView.animate(withDuration: 0.45, delay: 0.1, options: .curveEaseOut, animations: {
                self.wkWebView?.alpha = 1
                self.wkWebView?.transform = .identity
            })
        }
    }

    // MARK: - WebView setup

    func initialLoad() {
        guard let wkWebView = wkWebView else {
            createWkWebView()
            return
        }
        Task(priority: .high) {
            SplashAnimationView.postStatus("Preparing auth…")
            await urlFactory?.prepareForInitialLoad()
            do {
                SplashAnimationView.postStatus("Loading app…")
                guard let url = try await urlFactory?.getInitialUrl() else {
                    throw WebViewError(message: "Could't get initial webView url.")
                }

                let request = URLRequest(url: url)
                wkWebView.load(request)

                self.wkWebView = wkWebView

            } catch let error {
                delegate?.onError(error)
            }
        }
    }

    private func setupView(for webView: WKWebView, colorScheme scheme: ColorScheme) {
        let color  = AppColors(scheme: scheme)
        // Use the keyboard-matching colour so the iOS keyboard's rounded
        // corners blend in and the safe-area gap below the bottom row disappears.
        view.backgroundColor = color.keyboardBackground

        if appType == .web {
            webView.scrollView.backgroundColor = color.backgroundColor
        }

        webView.backgroundColor = .clear

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor).isActive = true
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    private func getNativeAppScript() -> WKUserScript {
        let source = """
        window.__capital_wizard_native = { platform: 'ios' };
        document.documentElement.classList.add('cw-native-ios');
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    // (Roman) TODO: Remove this. WebView should be able to adjust itself.
    /// Remove the iOS form accessory bar (Previous/Next/Done toolbar) above the keyboard.
    /// This is done by swizzling the `inputAccessoryView` on the inner WKContentView.
    private func removeInputAccessoryView() {
        guard let webView = wkWebView,
              let contentView = webView.scrollView.subviews.first(where: {
                  String(describing: type(of: $0)).hasPrefix("WKContentView")
              }) else { return }

        let noInputAccessoryViewClass: AnyClass = {
            let className = "NoInputAccessoryView_\(UUID().uuidString.prefix(8))"
            guard let baseClass = object_getClass(contentView) else { return type(of: contentView) }
            let newClass: AnyClass = objc_allocateClassPair(baseClass, className, 0)!

            let nilBlock: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
            let nilIMP = imp_implementationWithBlock(nilBlock)
            let selector = #selector(getter: UIResponder.inputAccessoryView)
            let method = class_getInstanceMethod(UIView.self, selector)!
            let typeEncoding = method_getTypeEncoding(method)
            class_addMethod(newClass, selector, nilIMP, typeEncoding)

            objc_registerClassPair(newClass)
            return newClass
        }()

        object_setClass(contentView, noInputAccessoryViewClass)
    }

    private func getZoomDisableScript() -> WKUserScript {
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';" +
            "var head = document.getElementsByTagName('head')[0];" + "head.appendChild(meta);"
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    func updateColorScheme(_ scheme: ColorScheme) {
        let color  = AppColors(scheme: scheme)
        view.backgroundColor = color.keyboardBackground

        if appType == .web {
            wkWebView?.scrollView.backgroundColor = color.backgroundColor
        }
    }

    func hideWebView() {
        readyTimeoutWork?.cancel()
        readyTimeoutWork = nil
        splashView?.removeFromSuperview()
        splashView = nil
        wkWebView?.stopLoading()
        wkWebView?.closeAllMediaPresentations()
        wkWebView?.navigationDelegate = nil
        wkWebView?.uiDelegate = nil
        wkWebView?.configuration.userContentController.removeAllUserScripts()
        wkWebView?.configuration.userContentController.removeAllScriptMessageHandlers()
        wkWebView?.removeFromSuperview()
        wkWebView = nil
    }

    func send(json: String) async throws -> Any? {
        try await wkWebView?.evaluateJavaScript(json)
    }

    func reload(with url: URL? = nil) {
        webViewDidLoaded = false
        if let url = url {
            let request = URLRequest(url: url)
            wkWebView?.load(request)
            return
        }
        wkWebView?.reload()
    }

    func hardRealod() {
        wkWebView?.reloadFromOrigin()
    }

    /// Probe whether the live web content is responsive and has actually rendered.
    /// Calls back with `false` if the web-content process is dead (the JS eval
    /// errors out) or the app rendered nothing into `#root` (a blank screen). Used
    /// on foreground to decide whether a reload is genuinely needed, so a healthy
    /// app is never reloaded.
    func pingWebContent(_ completion: @escaping (Bool) -> Void) {
        guard let wkWebView = wkWebView else {
            completion(false)
            return
        }
        let probe = "(function(){try{var r=document.getElementById('root');"
            + "return !!(window.__capital_wizard && r && r.childElementCount > 0);}"
            + "catch(e){return false;}})()"
        wkWebView.evaluateJavaScript(probe) { result, error in
            if let error = error {
                CWLog.shared.log("Health ping error: \(error.localizedDescription)", category: "WebView")
                completion(false)
                return
            }
            completion((result as? Bool) ?? false)
        }
    }
}

extension WebViewApplicationController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Handle target="_blank" links by loading in the same view
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            if let url = navigationAction.request.url {
                let baseHost = URL(string: WebViewApplicationConst.applicationBaseUrl)?.host
                if let host = url.host, host != baseHost {
                    UIApplication.shared.open(url)
                } else {
                    webView.load(navigationAction.request)
                }
            }
        }
        return nil
    }
}

extension WebViewApplicationController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewDidLoaded = true
        CWLog.shared.log("WebView navigation finished", category: "WebView")
        SplashAnimationView.postStatus("Waiting for app ready…")
        onLoadedEvent.invoke(())
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let baseHost = URL(string: WebViewApplicationConst.applicationBaseUrl)?.host

        if navigationAction.navigationType == .linkActivated,
           let host = url.host, host != baseHost {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        CWLog.shared.log("WebView provisional navigation failed: \(error.localizedDescription)", category: "WebView")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Ignore a termination reported for a WebView we have already replaced
        // (e.g. the old one dying just as a recovery reload starts) — otherwise the
        // in-flight preloader gets torn down and the W animation restarts.
        guard webView == wkWebView else { return }
        delegate?.onWebViewTerminated()
    }
}
