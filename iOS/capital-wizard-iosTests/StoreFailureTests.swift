import Testing
@testable import capital_wizard_ios

struct StoreFailureTests {
    @Test func authenticationFailureRequiresSigningInAgain() {
        #expect(StoreFailure.response(status: 401).code == "session_unavailable")
    }

    @Test func accessAndAvailabilityHaveDifferentRecoveryMessages() {
        #expect(StoreFailure.response(status: 403).code == "access_denied")
        #expect(StoreFailure.response(status: 503).code == "payments_unavailable")
    }

    @Test func unexpectedResponsesDoNotInventAnAuthenticationFailure() {
        for status in [400, 404, 429, 500, 502, 504] {
            #expect(StoreFailure.response(status: status).code == "server_unavailable")
        }
    }
}
