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
    
    weak var wkWebView: WKWebView?
    
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
        print("\(try data.apiCall)")
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
            case .auth:
                break
            }
        }
    }
    
    private func parseSystemResponse(_ dict: Dictionary<String, Any>) {
        guard let eventName = dict["eventName"] as? String else {
            return
        }
        
        if eventName == "api-ready" {
            finilizeLoad()
        }
    }
}
