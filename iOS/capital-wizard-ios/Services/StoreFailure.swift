/// Safe, stable bridge codes. Never expose server bodies, sessions or receipts.
struct StoreFailure: Error {
    let code: String

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
