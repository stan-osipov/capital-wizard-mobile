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
    case kv
    case navigate
    case push
    case pushOpened
    case pushStatus
    case foreground
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

/// Description: native → web push registration.
///
/// Hands over the APNs device token so the web app can store it against the
/// signed-in account. Sent whether or not a token was issued: a payload with no
/// `token` is how a refused permission is reported, and the web side simply
/// stops waiting.
struct WebApicPushCall: WebApiCall {
    var type: WebApiCallType = .push

    var registration: PushRegistration?
    /// Why there is no token — `denied` or `error` — so the web app's decline
    /// log can tell a real refusal from an APNs hiccup. Only embedded in the
    /// token-less answer.
    var failureReason: String?

    init(registration: PushRegistration?, failureReason: String? = nil) {
        self.registration = registration
        self.failureReason = failureReason
    }

    var dictJson: Dictionary<String, Any> {
        guard let registration = registration else {
            var dict: Dictionary<String, Any> = ["platform": "ios", "permission": "denied"]
            if let reason = failureReason, !reason.isEmpty {
                dict["reason"] = reason
            }
            return dict
        }
        return [
            "platform": "ios",
            "permission": "granted",
            "token": registration.token,
            "environment": registration.environment,
            "bundleId": registration.bundleId,
            "deviceName": registration.deviceName,
            "appVersion": registration.appVersion,
        ]
    }

    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: []) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            return "window.__capital_wizard && window.__capital_wizard.push && window.__capital_wizard.push(\(string));"
        }
    }
}

/// Description: native → web tap report. Hands over the `sendId`s of tapped
/// notifications so the web app can count them via its `track_push_open` RPC —
/// the web side owns validation and auth; the shell is only the courier.
///
/// Guarded on the web side: older builds predate `pushOpened` and simply have
/// no such function, so the call no-ops rather than throwing.
struct WebApicPushOpenedCall: WebApiCall {
    var type: WebApiCallType = .pushOpened

    var sendIds: [String]

    init(sendIds: [String]) {
        self.sendIds = sendIds
    }

    var dictJson: Dictionary<String, Any> {
        ["platform": "ios", "sendIds": sendIds]
    }

    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: []) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            return "window.__capital_wizard && window.__capital_wizard.pushOpened && window.__capital_wizard.pushOpened(\(string));"
        }
    }
}

/// Description: native → web "the app just came back to the foreground".
///
/// `document.visibilitychange` would be the obvious way for the web app to
/// notice this and it is not dependable: this shell does not drive the
/// WebView's own pause/resume, so whether WebKit flips visibilityState on an
/// app switch is up to the platform. Screens describing state changed from
/// OUTSIDE the app — the import notification card, which reports an OS
/// permission the user may have just left to flip — need a signal that fires.
///
/// Guarded on the web side: older builds have no `foreground` function and the
/// call no-ops. The web app also still listens to visibilitychange, so both
/// firing costs one guarded read rather than two.
struct WebApicForegroundCall: WebApiCall {
    var type: WebApiCallType = .foreground

    var dictJson: Dictionary<String, Any> {
        ["platform": "ios"]
    }

    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: []) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            return "window.__capital_wizard && window.__capital_wizard.foreground && window.__capital_wizard.foreground(\(string));"
        }
    }
}

/// Description: native → web answer to `request-push-status` — the OS notification
/// permission as it stands right now.
///
/// The web app cannot work this out for itself: its `push_devices` row survives
/// the user switching notifications off in Settings, so the registry reads
/// "reachable" while the phone silently discards every send. Only the shell can
/// see the real state.
///
/// Guarded on the web side: older builds have no `pushStatus` function, so the
/// call no-ops and the web app treats the unanswered question as "unknown"
/// rather than as "off".
struct WebApicPushStatusCall: WebApiCall {
    var type: WebApiCallType = .pushStatus

    /// One of `granted` / `denied` / `undetermined`.
    var permission: String

    init(permission: String) {
        self.permission = permission
    }

    var dictJson: Dictionary<String, Any> {
        ["platform": "ios", "permission": permission]
    }

    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: []) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            return "window.__capital_wizard && window.__capital_wizard.pushStatus && window.__capital_wizard.pushStatus(\(string));"
        }
    }
}

/// Description: native → web route push, for a link tapped while the WebView was
/// already running. Routing in place keeps the session and skips the full reload
/// a fresh `load(url)` would cost.
///
/// Guarded on the web side too: older builds predate `navigate` and simply have
/// no such function, so the call no-ops rather than throwing.
struct WebApicNavigateCall: WebApiCall {
    var type: WebApiCallType = .navigate

    var path: String

    init(path: String) {
        self.path = path
    }

    var dictJson: Dictionary<String, Any> {
        ["path": path]
    }

    var apiCall: String {
        get throws {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dictJson, options: []) else {
                throw ApiError(message: "Couldn't get json data from dictJson for \(type) api call.")
            }
            guard let string = String(data: jsonData, encoding: .utf8) else {
                throw ApiError(message: "Couldn't get string from json data for \(type) api call.")
            }
            return "window.__capital_wizard && window.__capital_wizard.navigate && window.__capital_wizard.navigate(\(string));"
        }
    }
}
