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

    enum RefreshingState {
        case start
        case onReleaseFinger
        case cancel
    }

    private var wkWebView: WKWebView?

    var onLoadedEvent: Event<Void> = Event()

    var webViewDidLoaded: Bool   = false
    var appType: ApplicationType = .web
    var id:      String          = ""

    var contentController: WKUserContentController?
    weak var urlFactory:   UrlFactory?
    weak var delegate:     WebViewControllerDelegate?

    private var splashView:     UIView?
    private var refreshControl: UIRefreshControl?
    private var readyTimeoutWork: DispatchWorkItem?

    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var isDarkMode: Bool {
        windowsService?.colorScheme.isDarkMode ?? false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        createWkWebView(withPreloader: true)
    }

    func createWkWebView(withPreloader hasPreloader: Bool = false) {
        guard let contentController = contentController else {
            return
        }
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

        wkWebView.scrollView.bounces      = true
        wkWebView.scrollView.scrollsToTop = false

        let refreshControl  = UIRefreshControl()
        self.refreshControl = refreshControl

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.gray,
            .font: UIFont.systemFont(ofSize: 14)
        ]
        let attributedTitle = NSAttributedString(string: "Pull to Refresh", attributes: attributes)
        refreshControl.attributedTitle = attributedTitle

        refreshControl.addTarget(self, action: #selector(reloadWebView(_:)), for: .valueChanged)

        wkWebView.scrollView.refreshControl = refreshControl

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

    @objc private func reloadWebView(_ sender: UIRefreshControl) {
        webViewDidLoaded = false
        wkWebView?.reloadFromOrigin()
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
        refreshControl?.removeTarget(self, action: #selector(reloadWebView(_:)), for: .valueChanged)
        refreshControl = nil
        wkWebView?.stopLoading()
        wkWebView?.closeAllMediaPresentations()
        wkWebView?.navigationDelegate = nil
        wkWebView?.uiDelegate = nil
        wkWebView?.configuration.userContentController.removeAllUserScripts()
        wkWebView?.configuration.userContentController.removeAllScriptMessageHandlers()
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
        SplashAnimationView.postStatus("Waiting for app ready…")
        onLoadedEvent.invoke(())
        guard let scrollView = wkWebView?.scrollView else {
            return
        }
        guard !scrollView.isDragging && !scrollView.isTracking else {
            return
        }
        refreshControl?.endRefreshing()
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
        refreshControl?.endRefreshing()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        delegate?.onWebViewTerminated()
    }
}
