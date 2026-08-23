package com.capitalwizard.android.services

import android.net.Uri
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.Event

/**
 * Turns an inbound link into a web-app route and holds it until the WebView is
 * in a position to show it. Mirrors the iOS `DeepLinkService`.
 *
 * Two ways in:
 *  * an **app link** — `https://app.capital-wizard.com/<path>` — which Android
 *    routes here once `assetlinks.json` on that domain verifies this package.
 *    This is the path real invite links take.
 *  * the **custom scheme** — `capital-wizard-android://open?path=/join/abc` — a
 *    fallback for contexts where app-link verification hasn't happened. The
 *    OAuth callback shares the scheme under the `auth` host, so they never
 *    collide.
 *
 * A link can land long before we can act on it: the user may be signed out, or
 * the WebView may not exist yet. So the path is *stashed* rather than delivered,
 * and whoever becomes ready first consumes it.
 */
class DeepLinkService {

    companion object {
        /** Host declared in the app-link intent filter. */
        const val LINK_HOST = "app.capital-wizard.com"
        /**
         * The marketing apex, claimed for referral links ONLY — the manifest
         * narrows it to `/r` and the assetlinks file is shared with the app
         * host. iOS expresses the same narrowing as an allow-list inside its
         * association file, because there the domain default is the reverse.
         */
        const val REFERRAL_HOST = "capital-wizard.com"
        /** Web route a referral code lands on. The register screen reads `ref`. */
        const val REFERRAL_ROUTE = "/auth/register"
        /** Custom scheme registered in the manifest. */
        const val CUSTOM_SCHEME = "capital-wizard-android"
        /** Custom-scheme host reserved for routing. `auth` belongs to AuthService. */
        const val ROUTE_HOST = "open"

        /**
         * Maps a supported URI onto a root-relative web-app route, or `null` when
         * the URI isn't one we route.
         */
        fun appPath(uri: Uri): String? = when (uri.scheme?.lowercase()) {
            "https", "http" -> when (uri.host?.lowercase()) {
                LINK_HOST -> normalized(uri.path, uri.query, uri.fragment)
                // The apex is claimed for one thing only, so it is TRANSLATED
                // rather than passed through: `capital-wizard.com/r/STAN-8F2K`
                // is a page on the marketing site and the app has no such
                // route. It becomes the sign-up screen with the code attached.
                REFERRAL_HOST -> referralCode(uri.path)?.let { "$REFERRAL_ROUTE?ref=$it" }
                else -> null
            }

            CUSTOM_SCHEME -> customSchemePath(uri)

            else -> null
        }

        /**
         * The code out of `/r/<CODE>`, upper-cased, or `null` when the path is
         * not a referral link. The alphabet matches the database's own check
         * constraint — anything else is not a code we could resolve anyway.
         */
        fun referralCode(path: String?): String? {
            val parts = path.orEmpty().split("/").filter { it.isNotEmpty() }
            if (parts.size != 2 || !parts[0].equals("r", ignoreCase = true)) return null
            val code = parts[1].uppercase()
            if (code.length !in 3..32) return null
            if (!code.all { it.isLetterOrDigit() && it.code < 128 || it == '-' }) return null
            if (code.first() == '-') return null
            return code
        }

        /** `capital-wizard-android://open?path=/join/abc` → `/join/abc`. */
        private fun customSchemePath(uri: Uri): String? {
            // `capital-wizard-android://auth/callback` is the OAuth leg — not ours.
            if (uri.host?.lowercase() != ROUTE_HOST) return null

            val raw = runCatching { uri.getQueryParameter("path") }.getOrNull() ?: return null
            val inner = runCatching { Uri.parse(raw) }.getOrNull() ?: return null

            // Reject anything carrying its own scheme or host: `path` must be a
            // route on our own origin, never a way to point the WebView elsewhere.
            // This also catches protocol-relative `//evil.test`, which parses with
            // a host and no scheme.
            if (inner.scheme != null || inner.host != null) return null

            return normalized(inner.path, inner.query, inner.fragment)
        }

        /**
         * Validates and reassembles a route. Rejects anything not rooted at `/`.
         * A bare `/` returns `null`: the app already opens there, so there is
         * nothing to restore.
         */
        private fun normalized(path: String?, query: String?, fragment: String?): String? {
            if (path.isNullOrEmpty() || !path.startsWith("/") || path.startsWith("//") || path == "/") {
                return null
            }
            return buildString {
                append(path)
                if (!query.isNullOrEmpty()) append("?").append(query)
                if (!fragment.isNullOrEmpty()) append("#").append(fragment)
            }
        }
    }

    /**
     * Fired when a link arrives. Subscribers that can act immediately should call
     * [consumePendingPath]; ignoring the event leaves the path stashed.
     */
    val onDeepLink = Event<String>()

    private var pendingPath: String? = null

    /** Whether a route is waiting to be shown. */
    val hasPendingPath: Boolean get() = pendingPath != null

    /**
     * Accepts [uri] if it resolves to an app route. Returns `false` when it is not
     * ours — the OAuth callback, another host, or a bare root link — so the caller
     * can pass it on.
     */
    fun handle(uri: Uri?): Boolean {
        val path = uri?.let { appPath(it) } ?: return false

        CWLog.log("Deep link received → $path", category = "DeepLink")
        pendingPath = path
        onDeepLink.invoke(path)
        return true
    }

    /**
     * Accepts a route that arrived without a URI around it — today, the `route`
     * carried by a tapped push notification. Same stash-and-announce behaviour
     * as [handle], and the same validation: a value carrying its own scheme or
     * host is refused, so a notification payload can't point the WebView off our
     * origin.
     */
    fun handleRoutePath(raw: String): Boolean {
        val inner = runCatching { Uri.parse(raw) }.getOrNull() ?: return false
        if (inner.scheme != null || inner.host != null) return false
        val path = normalized(inner.path, inner.query, inner.fragment) ?: return false

        CWLog.log("Route received → $path", category = "DeepLink")
        pendingPath = path
        onDeepLink.invoke(path)
        return true
    }

    /**
     * Returns the stashed route and clears it, so a link is only ever applied
     * once — a later reload must not silently re-navigate the user.
     */
    fun consumePendingPath(): String? {
        val path = pendingPath ?: return null
        pendingPath = null
        CWLog.log("Deep link consumed → $path", category = "DeepLink")
        return path
    }
}
