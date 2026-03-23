//
//  WebApiResponses.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

/// Description: web event wrapper.
struct WebEventCallback {
    var data: Any?
    var error: WebApiError?
}

/// Description: web api run method result wrapper.
struct WebApiRunResult {
    var data: Any?
    var error: String?
}

struct WebConsoleCallback {
    var data: Any?
    var error: WebApiError?
}
