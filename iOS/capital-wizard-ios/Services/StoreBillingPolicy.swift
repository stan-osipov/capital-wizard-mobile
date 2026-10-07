/// Controls the synchronous bridge hint. StoreService verifies the signed app
/// environment before Release purchases; the server verifies every transaction.
enum StoreBillingPolicy {
    static func isAvailable(isDebugBuild: Bool, receiptName: String?) -> Bool {
        isDebugBuild || receiptName == "sandboxReceipt"
    }
}
