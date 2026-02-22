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
