package com.capitalwizard.android.services

import com.android.billingclient.api.BillingClient.BillingResponseCode

/** Safe, stable bridge codes. Never expose server bodies, sessions or receipts. */
class StoreFailure(val code: String) : Exception(code) {
    companion object {
        fun billing(code: Int) = StoreFailure(when (code) {
            BillingResponseCode.BILLING_UNAVAILABLE, BillingResponseCode.FEATURE_NOT_SUPPORTED -> "store_not_allowed"
            BillingResponseCode.DEVELOPER_ERROR -> "store_configuration_error"
            BillingResponseCode.ITEM_UNAVAILABLE -> "product_unavailable"
            else -> "store_unavailable"
        })

        // Mirror StoreKit's explicit purchase refusals. Transport errors and
        // ITEM_ALREADY_OWNED remain uncertain and must reconcile before retry.
        fun isPurchaseRejected(code: Int) = code in listOf(
            BillingResponseCode.BILLING_UNAVAILABLE, BillingResponseCode.FEATURE_NOT_SUPPORTED,
            BillingResponseCode.DEVELOPER_ERROR, BillingResponseCode.ITEM_UNAVAILABLE,
        )

        fun response(status: Int) = StoreFailure(when (status) {
            401 -> "session_unavailable"
            403 -> "access_denied"
            503 -> "payments_unavailable"
            else -> "server_unavailable"
        })
    }
}
