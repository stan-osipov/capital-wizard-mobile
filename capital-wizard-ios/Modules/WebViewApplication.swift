//
//  WebViewApplication.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import WebKit

struct WebViewApplicationConst {
    static let baseUrlKey = "applicationBaseUrl"
    static let applicationBaseUrl    = "http://192.168.0.118:3005/"
    static let contentControllerName = "iosCW"
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
    
    lazy var webViewCommunication: WebViewCommunication  = WebViewCommunication()
    lazy var windowsService:       WindowsService?       = ServiceManager.shared.getService()
    lazy var applicationService:   ApplicationService?   = ServiceManager.shared.getService()

    private lazy var onColorChangeHandler:   EventCallback   = EventCallback(onColorSchemeChanged(_:))

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
    }
    
    func stop() {
        isActive = false
        
        webViewController?.hideWebView()
        if UIDevice.current.userInterfaceIdiom == .phone {
            controller?.dismiss(animated: false)
        }
        
        windowsService?.onColorSchemeChanged -= onColorChangeHandler
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
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
        if needReload {
            needReload = false
            webViewController?.createWkWebView(withPreloader: true)
        }
    }
 
    private func onColorSchemeChanged(_ scheme: ColorScheme) {
        guard webViewCommunication.isReady else {
            return
        }
        webViewController?.updateColorScheme(scheme)
        updateWebViewColorScheme(to: scheme)
    }

    
    private func updateWebViewColorScheme(to scheme: ColorScheme) {
    }
}

extension WebViewApplication: UrlFactory {
    func prepareForInitialLoad() async {
        let authService: AuthService? = ServiceManager.shared.getService()
        guard let session = try? await authService?.client.session else { return }
        await MainActor.run {
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
        
        print("[BUG] \(url)")
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
        print(error)
    }
    
    func willStartLoad(wkWebView: WKWebView) {
        webViewCommunication.wkWebView = wkWebView
    }
    
    func onWebViewTerminated() {
        didLogin = false
        webViewController?.hideWebView()
        webViewCommunication.clearData()
        webViewController?.contentController = webViewCommunication.contentController
        if isActive {
            onError(WebViewError(message: "Web view for \(id) did terminate"))
            webViewController?.createWkWebView(withPreloader: true)
        } else {
            print("Web view for \(id) did terminate")
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
