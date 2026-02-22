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
    
    private var preloader:      Preloader?
    private var refreshControl: UIRefreshControl?
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    private var isDarkMode: Bool {
        windowsService?.colorScheme.isDarkMode ?? false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let preloader  = Preloader(in: view)
        self.preloader = preloader
        self.view.addSubview(preloader)
        
        createWkWebView(withPreloader: true)
    }
    
    func createWkWebView(withPreloader hasPreloader: Bool = false) {
        guard let contentController = contentController else {
            return
        }
        
        if hasPreloader {
            preloader?.show()
        }
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.userContentController.addUserScript(self.getZoomDisableScript())
        
        let wkWebView = WKWebView(frame: self.view.frame, configuration: config)
        wkWebView.uiDelegate = self
        
        wkWebView.navigationDelegate = self
        if #available(iOS 16.4, *) {
            wkWebView.isInspectable = true
        } else {
            // Fallback on earlier versions
        }

        delegate?.willStartLoad(wkWebView: wkWebView)
        
        let scheme = windowsService?.colorScheme ?? .light
        
        wkWebView.scrollView.delegate = self
        wkWebView.scrollView.bounces  = true
        
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
        
        setupView(for: wkWebView, colorScheme: scheme, withPreloader: hasPreloader)

        self.wkWebView = wkWebView
        initialLoad()
    }
    
    func initialLoad() {
        guard let wkWebView = wkWebView else {
            createWkWebView()
            return
        }
        Task(priority: .high) {
            await urlFactory?.prepareForInitialLoad()
            do {
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
    
    private func setupView(for webView: WKWebView, colorScheme scheme: ColorScheme, withPreloader hasPreloader: Bool) {
        let color  = AppColors(scheme: scheme)
        view.backgroundColor = color.backgroundColor

        if appType == .web {
            webView.scrollView.backgroundColor = color.backgroundColor
        }
        
        webView.backgroundColor = .clear

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor).isActive = true
        if UIDevice.current.userInterfaceIdiom == .phone {
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        } else {
            webView.topAnchor.constraint(equalTo: view.topAnchor, constant: -5).isActive = true
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        }
        
        if let preloader = preloader, hasPreloader {
            view.bringSubviewToFront(preloader)
        }
    }
    
    // (Roman) TODO: Remove this. WebView should be able to adjust itself.
    private func getZoomDisableScript() -> WKUserScript {
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" + "head.appendChild(meta);"
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
    
    @objc private func reloadWebView(_ sender: UIRefreshControl) {
    }
    
    func updateColorScheme(_ scheme: ColorScheme) {
        let color  = AppColors(scheme: scheme)
        view.backgroundColor = color.backgroundColor

        if appType == .web {
            wkWebView?.scrollView.backgroundColor = color.backgroundColor
        }
    }
    
    func hideWebView() {
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

extension WebViewApplicationController: UIScrollViewDelegate {
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if let refresh = refreshControl, refresh.isRefreshing {
            hardRealod()
            refresh.endRefreshing()
        }
    }
}
extension WebViewApplicationController: WKUIDelegate {
}

extension WebViewApplicationController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        preloader?.hide()
        webViewDidLoaded = true
        onLoadedEvent.invoke(())
        guard let scrollView = wkWebView?.scrollView else {
            return
        }
        guard !scrollView.isDragging && !scrollView.isTracking else {
            return
        }
        refreshControl?.endRefreshing()
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        delegate?.onWebViewTerminated()
    }
}
