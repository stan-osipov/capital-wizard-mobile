package com.capitalwizard.android.services

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import com.android.billingclient.api.BillingClient.BillingResponseCode

class StoreFailureTest {
    @Test fun explicitPlayRejectionsAreNotPendingPayments() {
        val refusals = mapOf(
            BillingResponseCode.BILLING_UNAVAILABLE to "store_not_allowed",
            BillingResponseCode.FEATURE_NOT_SUPPORTED to "store_not_allowed",
            BillingResponseCode.DEVELOPER_ERROR to "store_configuration_error",
            BillingResponseCode.ITEM_UNAVAILABLE to "product_unavailable",
        )
        for ((code, message) in refusals) {
            assertEquals(message, StoreFailure.billing(code).code)
            assertTrue(StoreFailure.isPurchaseRejected(code))
        }
    }

    @Test fun uncertainPlayOutcomesStillRequireReconciliation() {
        for (code in listOf(BillingResponseCode.NETWORK_ERROR, BillingResponseCode.SERVICE_DISCONNECTED,
            BillingResponseCode.SERVICE_UNAVAILABLE, BillingResponseCode.ERROR, BillingResponseCode.ITEM_ALREADY_OWNED, 999)) {
            assertFalse(StoreFailure.isPurchaseRejected(code))
            assertEquals("store_unavailable", StoreFailure.billing(code).code)
        }
    }

    @Test fun authenticationFailureRequiresSigningInAgain() {
        assertEquals("session_unavailable", StoreFailure.response(401).code)
    }

    @Test fun accessAndAvailabilityHaveDifferentRecoveryMessages() {
        assertEquals("access_denied", StoreFailure.response(403).code)
        assertEquals("payments_unavailable", StoreFailure.response(503).code)
    }

    @Test fun unexpectedResponsesDoNotInventAnAuthenticationFailure() {
        for (status in listOf(400, 404, 429, 500, 502, 504)) {
            assertEquals("server_unavailable", StoreFailure.response(status).code)
        }
    }
}
