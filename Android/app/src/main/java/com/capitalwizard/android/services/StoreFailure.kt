package com.capitalwizard.android.services

/** Safe, stable bridge codes. Never expose server bodies, sessions or receipts. */
class StoreFailure(val code: String) : Exception(code) {
    companion object {
        fun response(status: Int) = StoreFailure(when (status) {
            401 -> "session_unavailable"
            403 -> "access_denied"
            503 -> "payments_unavailable"
            else -> "server_unavailable"
        })
    }
}
