package com.capitalwizard.android.services

import org.junit.Assert.assertEquals
import org.junit.Test

class StoreFailureTest {
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
