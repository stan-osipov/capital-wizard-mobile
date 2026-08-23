package com.capitalwizard.android.services

import android.content.Context
import android.content.SharedPreferences
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.capitalwizard.android.utils.CWLog

/**
 * Recovers a referral code that was attached to the Play listing URL.
 *
 * The problem this solves: somebody taps `capital-wizard.com/r/STAN-8F2K`
 * without the app installed. The App Link cannot fire, so the claim page sends
 * them to Play with `?referrer=ref%3DSTAN-8F2K`. They install, open the app —
 * and the browser that knew the code is a different storage jar entirely. Play
 * is the only thing that crossed the install, so Play is where the code has to
 * come from.
 *
 * **There is deliberately no iOS counterpart.** Apple provides no install-time
 * payload of any kind — campaign parameters on an App Store URL reach App
 * Analytics, never the app. On iOS the code is carried by the person instead:
 * printed on the claim page, and typed into the sign-up screen, which accepts
 * it for a week after the account is created.
 *
 * Read exactly once per install. The referrer string is retained by Play
 * indefinitely, so without a latch this would re-apply somebody's referral
 * every single launch.
 */
class InstallReferrerService(private val context: Context) {

    companion object {
        private const val PREFS = "cw_install_referrer"
        private const val KEY_CHECKED = "checked"

        /**
         * The `ref` value out of a Play referrer string, or `null`.
         *
         * The string is a URL query — `utm_source=x&ref=STAN-8F2K` — and Play
         * also sends `utm_source=google-play&utm_medium=organic` for an ordinary
         * organic install, which carries no `ref` and must simply be ignored.
         */
        fun referralCode(referrer: String?): String? {
            if (referrer.isNullOrBlank()) return null
            val raw = referrer.split("&")
                .firstOrNull { it.startsWith("ref=", ignoreCase = true) }
                ?.substringAfter("=")
                ?: return null
            val decoded = runCatching { java.net.URLDecoder.decode(raw, "UTF-8") }.getOrNull() ?: return null
            val code = decoded.trim().uppercase()
            if (code.length !in 3..32) return null
            if (!code.all { (it.isLetterOrDigit() && it.code < 128) || it == '-' }) return null
            if (code.first() == '-') return null
            return code
        }
    }

    private val prefs: SharedPreferences
        get() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Ask Play for the install referrer and, if it carries a code, stash the
     * sign-up route on [DeepLinkService] so the WebView opens there.
     *
     * Fire-and-forget: a first launch must never wait on Play, and every failure
     * mode here — no Play Store, an old Play version, a service disconnect — is
     * simply "no code", which the in-app code field already covers.
     */
    fun checkOnce(deepLinkService: DeepLinkService?) {
        if (prefs.getBoolean(KEY_CHECKED, false)) return

        val client = InstallReferrerClient.newBuilder(context).build()
        client.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                // Latch regardless of outcome: FEATURE_NOT_SUPPORTED and
                // SERVICE_UNAVAILABLE do not become supported later on this
                // install, and retrying every launch would burn a Play
                // connection for nothing.
                prefs.edit().putBoolean(KEY_CHECKED, true).apply()

                if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                    val referrer = runCatching { client.installReferrer.installReferrer }.getOrNull()
                    val code = referralCode(referrer)
                    if (code != null) {
                        CWLog.log("Install referrer carried a referral code", category = "Referral")
                        deepLinkService?.handleRoutePath("/auth/register?ref=$code")
                    } else {
                        CWLog.log("Install referrer had no referral code", category = "Referral")
                    }
                } else {
                    CWLog.log("Install referrer unavailable (code $responseCode)", category = "Referral")
                }
                runCatching { client.endConnection() }
            }

            override fun onInstallReferrerServiceDisconnected() {
                // Not retried on purpose — see checkOnce's contract.
            }
        })
    }
}
