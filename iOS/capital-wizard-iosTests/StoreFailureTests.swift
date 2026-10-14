import Testing
import StoreKit
@testable import capital_wizard_ios

struct StoreFailureTests {
    @Test func explicitStoreKitRejectionsAreNotPendingPayments() {
        #expect(StoreFailure.checkoutRejection(Product.PurchaseError.purchaseNotAllowed)?.code == "store_not_allowed")
        #expect(StoreFailure.checkoutRejection(Product.PurchaseError.productUnavailable)?.code == "product_unavailable")
    }

    @Test func uncertainStoreKitOutcomesStillRequireReconciliation() {
        #expect(StoreFailure.checkoutRejection(StoreKitError.unknown) == nil)
        #expect(StoreFailure.checkoutRejection(StoreFailure(code: "server_unavailable")) == nil)
    }
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
