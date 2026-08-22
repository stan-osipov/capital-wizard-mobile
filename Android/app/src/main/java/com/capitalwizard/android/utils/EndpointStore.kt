package com.capitalwizard.android.utils

import android.content.Context

/**
 * The sites the shell can be pointed at.
 *
 * Two builds of the same web app are served from two addresses: `main` lands on
 * app.capital-wizard.com, `dev` on dev.capital-wizard.com from a second Pages
 * repository. Everything else about them is identical — same shell, same bridge,
 * same accounts — so the endpoint is a *choice*, not a build flavour, and one
 * APK can be aimed at either.
 *
 * Mirrors `DEPLOY_ENDPOINTS` in the web app's src/lib/deployEnvironment.ts and
 * `AppEndpoint` in the iOS shell — change one, change all three.
 */
enum class AppEndpoint(val channel: String, val baseUrl: String) {
    /** Trailing slash included: callers concatenate a route straight onto this. */
    PRODUCTION("production", "https://app.capital-wizard.com/"),
    DEVELOPMENT("development", "https://dev.capital-wizard.com/");

    companion object {
        fun fromChannel(name: String?): AppEndpoint? =
            entries.firstOrNull { it.channel == name }
    }
}

/**
 * The chosen endpoint, persisted across launches.
 *
 * **Only a channel NAME is ever stored or accepted** — never a URL. The two
 * addresses live here, in the shell, so the web bridge (which any script in the
 * page can reach) can pick between them and nothing else. A stored value that no
 * longer names a channel falls back to production rather than being honoured.
 */
object EndpointStore {

    private const val PREFS_NAME = "cw_endpoint"
    private const val KEY_CHANNEL = "endpoint"

    fun current(context: Context): AppEndpoint {
        val saved = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_CHANNEL, null)
        return AppEndpoint.fromChannel(saved) ?: AppEndpoint.PRODUCTION
    }

    /** The base URL for the current endpoint — what every load starts from. */
    fun baseUrl(context: Context): String = current(context).baseUrl

    /**
     * Persists [endpoint]. Returns true only if this actually CHANGED it, so
     * callers can skip the WebView restart when a switch is a no-op.
     */
    fun set(context: Context, endpoint: AppEndpoint): Boolean {
        if (endpoint == current(context)) return false
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CHANNEL, endpoint.channel)
            .apply()
        CWLog.log("Endpoint set to ${endpoint.channel} (${endpoint.baseUrl})", category = "WebView")
        return true
    }

    /**
     * The allowlist gate: turns whatever the web sent into a known endpoint, or
     * null. Every value crossing the bridge goes through here.
     */
    fun endpointNamed(name: String?): AppEndpoint? = AppEndpoint.fromChannel(name)
}
