/// Controls bridge availability and rechecks the sandbox/account gate immediately
/// before checkout. Credit requires verification of the actual purchase, not the
/// unrelated app-download transaction (which can be missing in TestFlight).
enum StoreBillingPolicy {
    static func isAvailable(isDebugBuild: Bool, receiptName: String?) -> Bool {
        AppProduct.current.supportsStoreBilling && (isDebugBuild || receiptName == "sandboxReceipt")
    }

    static func validateCheckout(isDebugBuild: Bool, receiptName: String?, accountToken: String?, userId: String) throws {
        guard isAvailable(isDebugBuild: isDebugBuild, receiptName: receiptName) else {
            throw StoreFailure(code: "payments_unavailable")
        }
        guard !userId.isEmpty, accountToken == userId else {
            throw StoreFailure(code: "account_mismatch")
        }
    }
}
