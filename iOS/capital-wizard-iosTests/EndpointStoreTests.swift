//
//  EndpointStoreTests.swift
//  capital-wizard-iosTests
//

import Testing
import Foundation
@testable import capital_wizard_ios

/// Covers the endpoint allowlist. This is the security-bearing half of the
/// switch: whatever the web bridge sends is turned into one of exactly two
/// addresses here, or into nothing. Anything that let a NAME become an
/// arbitrary URL would hand any script in the page the whole WebView.
struct EndpointStoreTests {

    // MARK: - The allowlist

    @Test func acceptsTheTwoKnownChannels() {
        #expect(EndpointStore.endpoint(named: "production") == .production)
        #expect(EndpointStore.endpoint(named: "development") == .development)
    }

    @Test func rejectsAnUnknownChannel() {
        #expect(EndpointStore.endpoint(named: "staging") == nil)
        #expect(EndpointStore.endpoint(named: "") == nil)
        #expect(EndpointStore.endpoint(named: nil) == nil)
    }

    @Test func rejectsAChannelSpelledDifferently() {
        // Exact match only — a permissive comparison is how allowlists rot.
        #expect(EndpointStore.endpoint(named: "Production") == nil)
        #expect(EndpointStore.endpoint(named: " development ") == nil)
    }

    @Test func rejectsAUrlInPlaceOfAChannel() {
        // The point of naming a channel: a URL, ours or anyone else's, is not
        // a channel and can never become one.
        #expect(EndpointStore.endpoint(named: "https://app.capital-wizard.com/") == nil)
        #expect(EndpointStore.endpoint(named: "https://evil.example.com/") == nil)
    }

    @Test func rejectsANonStringPayload() {
        #expect(EndpointStore.endpoint(named: 1) == nil)
        #expect(EndpointStore.endpoint(named: ["production"]) == nil)
    }

    // MARK: - The addresses

    @Test func everyEndpointIsAnHttpsUrlEndingInASlash() {
        // Callers concatenate a route straight on, so the trailing slash is
        // structural, not cosmetic.
        for endpoint in AppEndpoint.allCases {
            #expect(endpoint.baseUrl.hasPrefix("https://"))
            #expect(endpoint.baseUrl.hasSuffix("/"))
            #expect(URL(string: endpoint.baseUrl) != nil)
        }
    }

    @Test func theTwoEndpointsAreDifferentHosts() {
        #expect(AppEndpoint.production.host == "app.capital-wizard.com")
        #expect(AppEndpoint.development.host == "dev.capital-wizard.com")
    }

    /// Serialized: these share one `UserDefaults.standard` key, and Swift
    /// Testing runs a suite's tests in parallel by default — which had them
    /// overwriting each other's fixture rather than testing the store.
    @Suite(.serialized) struct Persistence {

        @Test func remembersTheChosenEndpointAndReportsRealChangesOnly() {
            let original = EndpointStore.current
            defer { EndpointStore.set(original) }

            EndpointStore.set(.production)
            #expect(EndpointStore.current == .production)
            #expect(EndpointStore.baseUrl == AppEndpoint.production.baseUrl)

            // A real move reports true so the caller rebuilds the WebView…
            #expect(EndpointStore.set(.development) == true)
            #expect(EndpointStore.current == .development)
            #expect(EndpointStore.baseUrl == AppEndpoint.development.baseUrl)

            // …and setting what is already set reports false, so re-tapping the
            // active row does not restart the app.
            #expect(EndpointStore.set(.development) == false)
            #expect(EndpointStore.current == .development)
        }

        @Test func fallsBackToProductionWhenTheStoredValueNoLongerNamesAChannel() {
            let original = EndpointStore.current
            defer { EndpointStore.set(original) }

            UserDefaults.standard.set("staging", forKey: "applicationEndpoint")
            #expect(EndpointStore.current == .production)

            UserDefaults.standard.removeObject(forKey: "applicationEndpoint")
            #expect(EndpointStore.current == .production)
        }
    }
}
