//
//  WebApiCalls.swift
//

import Foundation

struct ApiError: Error, ErrorMessage {
    var message: String
    
    var description: String {
        "Error: [apiError] \(message)"
    }
}

/// Description: Web api method types.
enum WebApiCallType: String {
    case system
    case auth
    case theme
}

/// Description: Base web api call.
protocol WebApiCall {
    var type: WebApiCallType { get }
    
    var dictJson: Dictionary<String, Any> { get }
    var apiCall: String { get throws }
    
    var debugData: String { get throws }
}

/// Description: extension for getting apiCall string representation.
extension WebApiCall {
    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: .prettyPrinted) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            // (Roman) TODO: maybe move string to const.
            return "window.__capital_wizard.\(type)(\(string), '*');"
        }
    }
    
    var debugData: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: .prettyPrinted) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            
            return string
        }
    }
}

struct WebApicAuthCall: WebApiCall {
    var type: WebApiCallType = .auth

    var version:       Int  = 1
    var auth_token:    String
    var refresh_token: String

    init(authToken: String, refreshToken: String) {
        self.auth_token    = authToken
        self.refresh_token = refreshToken
    }
    
    var dictJson: Dictionary<String, Any> {
        ["auth_token": auth_token,
         "refresh_token": refresh_token]
    }
}

/// Description: native → web theme/accent push.
///
/// Unlike the generic two-arg calls, the web exposes the theme entry point as
/// `window.__capital_wizard.theme({ mode, accent })` (single argument), so this
/// overrides `apiCall` to match that shape exactly.
struct WebApicThemeCall: WebApiCall {
    var type: WebApiCallType = .theme

    var mode:   String
    var accent: String?

    init(mode: String, accent: String?) {
        self.mode   = mode
        self.accent = accent
    }

    var dictJson: Dictionary<String, Any> {
        var dict: Dictionary<String, Any> = ["mode": mode]
        if let accent = accent, !accent.isEmpty {
            dict["accent"] = accent
        }
        return dict
    }

    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: []) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            return "window.__capital_wizard && window.__capital_wizard.theme && window.__capital_wizard.theme(\(string));"
        }
    }
}
