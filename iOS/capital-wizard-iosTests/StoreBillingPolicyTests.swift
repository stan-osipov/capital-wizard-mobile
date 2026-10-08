import Testing
@testable import capital_wizard_ios

struct StoreBillingPolicyTests {
    @Test func testFlightReleaseAdvertisesBilling() {
        #expect(StoreBillingPolicy.isAvailable(isDebugBuild: false, receiptName: "sandboxReceipt"))
    }

    @Test func appStoreReleaseDoesNotAdvertiseBilling() {
        #expect(!StoreBillingPolicy.isAvailable(isDebugBuild: false, receiptName: "receipt"))
    }

    @Test func missingOrUnknownReleaseReceiptFailsClosed() {
        for receipt: String? in [nil, "", "SandboxReceipt", "sandboxReceipt.backup", "receipt/sandboxReceipt"] {
            #expect(!StoreBillingPolicy.isAvailable(isDebugBuild: false, receiptName: receipt))
        }
    }

    @Test func debugCanLoadProductsBeforeItsFirstPurchase() {
        #expect(StoreBillingPolicy.isAvailable(isDebugBuild: true, receiptName: nil))
    }
    @Test func sandboxCheckoutDoesNotRequireAnAppDownloadTransaction() throws {
        try StoreBillingPolicy.validateCheckout(isDebugBuild: false, receiptName: "sandboxReceipt",
            accountToken: "user", userId: "user")
    }

    @Test func checkoutRechecksTheReceiptRatherThanTrustingTheEarlierBridgeHint() {
        for receipt: String? in [nil, "receipt", ""] {
            #expect(throws: StoreFailure.self) {
                try StoreBillingPolicy.validateCheckout(isDebugBuild: false, receiptName: receipt,
                    accountToken: "user", userId: "user")
            }
        }
    }

    @Test func sandboxCheckoutRejectsMissingOrMismatchedAccountBinding() {
        for account: String? in [nil, "", "another-user"] {
            #expect(throws: StoreFailure.self) {
                try StoreBillingPolicy.validateCheckout(isDebugBuild: false, receiptName: "sandboxReceipt",
                    accountToken: account, userId: "user")
            }
        }
    }

    @Test func debugCheckoutStillRequiresTheServerAccountBinding() throws {
        try StoreBillingPolicy.validateCheckout(isDebugBuild: true, receiptName: nil,
            accountToken: "user", userId: "user")
        #expect(throws: StoreFailure.self) {
            try StoreBillingPolicy.validateCheckout(isDebugBuild: true, receiptName: nil,
                accountToken: nil, userId: "user")
        }
    }
}
