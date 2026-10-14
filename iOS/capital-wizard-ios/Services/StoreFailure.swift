import StoreKit

/// Safe, stable bridge codes. Never expose server bodies, sessions or receipts.
struct StoreFailure: Error {
    let code: String

    // Unlike Play's numeric BillingResult, StoreKit throws typed refusals.
    // Mirror Android: explicit rejections are errors, transport/verification
    // failures after checkout remain pending because a charge may exist.
    static func checkoutRejection(_ error: Error) -> StoreFailure? {
        guard let purchaseError = error as? Product.PurchaseError else { return nil }
        switch purchaseError {
        case .purchaseNotAllowed: return StoreFailure(code: "store_not_allowed")
        case .productUnavailable: return StoreFailure(code: "product_unavailable")
        default: return nil
        }
    }

    static func response(status: Int) -> StoreFailure {
        let code: String
        switch status {
        case 401: code = "session_unavailable"
        case 403: code = "access_denied"
        case 503: code = "payments_unavailable"
        default: code = "server_unavailable"
        }
        return StoreFailure(code: code)
    }
}
