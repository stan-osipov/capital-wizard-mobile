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
}
