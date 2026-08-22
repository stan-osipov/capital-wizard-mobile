package com.capitalwizard.android.webview

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.services.PushRegistration
import com.capitalwizard.android.services.PushService
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.AppEndpoint
import com.capitalwizard.android.utils.DeviceKvStore
import com.capitalwizard.android.utils.EndpointStore
import com.capitalwizard.android.utils.Event
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.utils.ThemePrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class WebViewBridge {

    val onAppReady = Event<Unit>()

    /**
     * Fires only when a `set-endpoint` actually MOVED the shell to the other
     * site; the Activity answers by restarting the web layer.
     */
    val onEndpointChanged = Event<AppEndpoint>()

    var webView: WebView? = null
    var isReady: Boolean = false
        private set

    companion object {
        const val JS_INTERFACE_NAME = "androidCW"

        /**
         * The site this shell is currently pointed at — production by default,
         * the development one when an admin has switched it (see [EndpointStore]).
         * Resolved per call rather than held in a constant so every caller — the
         * start URL, the deep-link loader, and both same-host navigation checks —
         * follows the switch together. A stale one of those would send in-app
         * links out to the system browser.
         */
        fun baseUrl(context: Context): String = EndpointStore.baseUrl(context)

        /**
         * Scheme + host (+ port) of [baseUrl] — the origin rule document-start
         * scripts are scoped to, so a script carrying this device's session can
         * only ever run on our own site, never on a page some redirect wandered
         * onto.
         */
        fun originRule(context: Context): String {
            val uri = Uri.parse(baseUrl(context))
            val port = if (uri.port != -1) ":${uri.port}" else ""
            return "${uri.scheme}://${uri.host}$port"
        }
    }

    /**
     * The session handed to the web app at DOCUMENT START, before any of the
     * page's own scripts run.
     *
     * The web app queues the call in `window.__capital_wizard._pending` and
     * drains it as `nativeBridge.ts` evaluates — which is before it wakes a
     * single service. That ordering is the whole point: services wake once, and
     * one that reads Supabase before the session lands stays signed-out for the
     * life of the document, leaving a shell with no space and no active app.
     *
     * `index.html` defines the same queue stub, but it sits at the end of
     * `<body>` and this runs before `<head>`, so the script defines the stub
     * itself; the page's own `window.__capital_wizard || {…}` then keeps ours.
     *
     * iOS states this as a `WKUserScript` at `.atDocumentEnd` instead — WebKit
     * has no document-start hook that would still let the page keep the queue,
     * and by document end the page's stub is up. Same contract, each platform's
     * own API.
     */
    fun getAuthSeedScript(accessToken: String, refreshToken: String): String {
        val json = JSONObject().apply {
            put("auth_token", accessToken)
            put("refresh_token", refreshToken)
        }
        return """
            window.__capital_wizard = window.__capital_wizard || {
                _pending: [],
                auth: function (p, o) { this._pending.push({ params: p, origin: o }); }
            };
            window.__capital_wizard.auth($json, '*');
        """.trimIndent()
    }

    fun injectAuthScript(accessToken: String, refreshToken: String) {
        val json = JSONObject().apply {
            put("auth_token", accessToken)
            put("refresh_token", refreshToken)
        }
        val js = "window.__capital_wizard.auth($json, '*');"
        webView?.evaluateJavascript(js, null)
    }

    fun clearState() {
        isReady = false
    }

    fun getNativeAppScript(): String {
        // `idiom` lets the web app pick its chrome: 'phone' → mobile chrome,
        // 'pad' (tablet) → desktop chrome with side-panel pinning disabled.
        val smallestWidthDp = webView?.context?.resources?.configuration?.smallestScreenWidthDp ?: 0
        val idiom = if (smallestWidthDp >= 600) "pad" else "phone"
        // `endpoint` names the site this WebView was pointed at, so the admin
        // header can state it rather than infer it. Read at injection time — the
        // switch restarts the Activity, so this always describes the live load.
        val endpoint = webView?.context?.let { EndpointStore.current(it).channel }
            ?: AppEndpoint.PRODUCTION.channel
        return """
            window.__capital_wizard_native = { platform: 'android', idiom: '$idiom', endpoint: '$endpoint' };
            document.documentElement.classList.add('cw-native-android');
        """.trimIndent()
    }

    /**
     * Native → web (pre-paint seed). Writes the saved web theme/accent into localStorage so
     * the page's inline pre-paint script (in index.html) picks them up and paints the correct
     * theme on first frame. Must run as early as possible — ideally at document start
     * ([android.webkit.WebViewClient.onPageStarted]) so it beats the inline script.
     *
     * Returns an empty string when nothing has been saved yet (first run before the user has
     * ever changed the theme), so the page falls through to its own default ("auto").
     *
     * Values are escaped via [JSONObject.quote], which yields a quoted JS string literal.
     */
    fun getThemeSeedScript(): String {
        val context = webView?.context ?: return ""
        val mode = ThemePrefs.getWebTheme(context)
        val accent = ThemePrefs.getWebAccent(context)
        if (mode.isNullOrBlank() && accent.isNullOrBlank()) return ""

        val sets = buildString {
            if (!mode.isNullOrBlank()) {
                append("localStorage.setItem('cw-theme', ${JSONObject.quote(mode)});")
            }
            if (!accent.isNullOrBlank()) {
                append("localStorage.setItem('cw-accent', ${JSONObject.quote(accent)});")
            }
        }
        return "(function(){try{$sets}catch(e){}})();"
    }

    /**
     * Native → web (pre-paint seed) for the generic device-store. Writes every saved KV pair
     * into localStorage BEFORE the page's inline pre-paint script runs (same rationale and
     * timing as [getThemeSeedScript]), so the web `deviceStore` reads them back transparently.
     * Empty string when nothing is saved.
     *
     * Keys and values are escaped via [JSONObject.quote] (valid quoted JS string literals).
     */
    fun getKvSeedScript(): String {
        val context = webView?.context ?: return ""
        val pairs = DeviceKvStore.all(context)
        if (pairs.isEmpty()) return ""

        val sets = buildString {
            for ((key, value) in pairs) {
                append("localStorage.setItem(${JSONObject.quote(key)}, ${JSONObject.quote(value)});")
            }
        }
        return "(function(){try{$sets}catch(e){}})();"
    }

    /**
     * Native → web (post-load fallback). Pushes the saved theme/accent through the web's
     * runtime hook `window.__capital_wizard.theme({ mode, accent })`, which applies it live
     * (no reload). Used after [android.webkit.WebViewClient.onPageFinished] in case the
     * pre-paint seed landed a hair too late. No-op (empty string) when nothing is saved.
     *
     * The call is guarded so it silently does nothing until the web has installed the real
     * `__capital_wizard.theme` handler (it is exposed by nativeBridge.ts on module load).
     */
    fun getThemePushScript(): String {
        val context = webView?.context ?: return ""
        val mode = ThemePrefs.getWebTheme(context)
        val accent = ThemePrefs.getWebAccent(context)
        if (mode.isNullOrBlank() && accent.isNullOrBlank()) return ""

        val payload = JSONObject().apply {
            if (!mode.isNullOrBlank()) put("mode", mode)
            if (!accent.isNullOrBlank()) put("accent", accent)
        }
        return """
            (function(){try{
                var cw = window.__capital_wizard;
                if (cw && typeof cw.theme === 'function') { cw.theme($payload); }
            }catch(e){}})();
        """.trimIndent()
    }

    /**
     * Best-effort runtime native → web route push: opens [path] in the live web app via
     * `window.__capital_wizard.navigate({…})`. Used for a link tapped while this WebView was
     * already running — routing in place keeps the session and skips the full reload a fresh
     * `loadUrl` would cost.
     *
     * Guarded like the theme push: older web builds predate `navigate` and simply have no such
     * function, so the call no-ops. Returns `false` when there is no live WebView to push into,
     * so the caller can fall back to loading the route outright.
     */
    fun pushNavigate(path: String): Boolean {
        val view = webView ?: return false
        val payload = JSONObject().apply { put("path", path) }
        view.evaluateJavascript(
            """
            (function(){try{
                var cw = window.__capital_wizard;
                if (cw && typeof cw.navigate === 'function') { cw.navigate($payload); }
            }catch(e){}})();
            """.trimIndent(),
            null
        )
        return true
    }

    /**
     * Best-effort runtime native → web push registration: hands the FCM token
     * (or a refusal) to the live web app via `window.__capital_wizard.push({…})`.
     *
     * Guarded like the theme push — an older web build has no such function and
     * the call simply no-ops. A payload with no `token` is how a refused
     * permission is reported; the web side stops waiting either way.
     * [failureReason] says WHY there is no token (`denied` / `unavailable` /
     * `error`) so the web's decline log never counts a Firebase-less build as a
     * user refusing.
     */
    fun pushRegistration(registration: PushRegistration?, failureReason: String? = null) {
        val view = webView ?: return
        val payload = JSONObject().apply {
            put("platform", "android")
            if (registration == null) {
                put("permission", "denied")
                if (!failureReason.isNullOrBlank()) put("reason", failureReason)
            } else {
                put("permission", "granted")
                put("token", registration.token)
                put("deviceName", registration.deviceName)
                put("appVersion", registration.appVersion)
                put("bundleId", registration.packageName)
            }
        }
        view.post {
            view.evaluateJavascript(
                """
                (function(){try{
                    var cw = window.__capital_wizard;
                    if (cw && typeof cw.push === 'function') { cw.push($payload); }
                }catch(e){}})();
                """.trimIndent(),
                null
            )
        }
    }

    /**
     * Best-effort runtime native → web tap report: hands the tapped
     * notifications' send ids to the live web app via
     * `window.__capital_wizard.pushOpened({…})`, which counts them through its
     * authenticated RPC. Guarded like the other pushes — an older web build has
     * no such function and the call simply no-ops.
     */
    fun pushOpened(sendIds: List<String>) {
        if (sendIds.isEmpty()) return
        val view = webView ?: return
        val payload = JSONObject().apply {
            put("platform", "android")
            put("sendIds", JSONArray(sendIds))
        }
        view.post {
            view.evaluateJavascript(
                """
                (function(){try{
                    var cw = window.__capital_wizard;
                    if (cw && typeof cw.pushOpened === 'function') { cw.pushOpened($payload); }
                }catch(e){}})();
                """.trimIndent(),
                null
            )
        }
    }

    /**
     * Best-effort runtime native → web push status: hands the OS notification
     * state to the live web app via `window.__capital_wizard.pushStatus({…})`.
     * Guarded like the other pushes — an older web build has no such function
     * and the call simply no-ops, which the web side reads as "unknown" rather
     * than as "off".
     */
    fun pushStatus(permission: String) {
        val view = webView ?: return
        val payload = JSONObject().apply {
            put("platform", "android")
            put("permission", permission)
        }
        view.post {
            view.evaluateJavascript(
                """
                (function(){try{
                    var cw = window.__capital_wizard;
                    if (cw && typeof cw.pushStatus === 'function') { cw.pushStatus($payload); }
                }catch(e){}})();
                """.trimIndent(),
                null
            )
        }
    }

    /**
     * Best-effort runtime native → web foreground ping via
     * `window.__capital_wizard.foreground({…})`.
     *
     * `document.visibilitychange` would be the obvious way for the web app to
     * notice a return from the background, and it is not dependable here: this
     * Activity does not call the WebView's own onPause/onResume (see the
     * deliberate no-needless-reload policy in WebViewActivity.onResume), so
     * whether Chromium flips visibilityState on an app switch is up to the
     * platform. Screens describing state changed from OUTSIDE the app — the
     * import notification card, which reports an OS permission the user may
     * have just left to flip — need a signal that actually fires.
     *
     * Guarded like the other pushes: an older web build has no `foreground`
     * function and the call simply no-ops. The web app also still listens to
     * visibilitychange, so both firing costs one guarded read rather than two.
     */
    fun pushForeground() {
        val view = webView ?: return
        val payload = JSONObject().apply { put("platform", "android") }
        view.post {
            view.evaluateJavascript(
                """
                (function(){try{
                    var cw = window.__capital_wizard;
                    if (cw && typeof cw.foreground === 'function') { cw.foreground($payload); }
                }catch(e){}})();
                """.trimIndent(),
                null
            )
        }
    }

    fun getZoomDisableScript(): String = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
        var head = document.getElementsByTagName('head')[0];
        head.appendChild(meta);
    """.trimIndent()

    // Called from JavaScript: window.androidCW.postMessage(jsonString)
    @JavascriptInterface
    fun postMessage(message: String) {
        try {
            val json = JSONObject(message)
            val type = json.optString("type")
            when (type) {
                "system" -> parseSystemMessage(json)
                "theme" -> parseThemeMessage(json)
                "kv" -> parseKvMessage(json)
                "auth" -> { /* reserved */ }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Web → native: { type: "theme", mode: "<light|dark|dark-soft|auto>", accent: "<id>" }.
     *
     * Persists the verbatim web values and mirrors the mode onto the native night mode.
     * This callback runs on a binder thread, so the [ThemePrefs.setFromWeb] call (which
     * eventually touches [androidx.appcompat.app.AppCompatDelegate]) is hopped onto the
     * WebView's main thread via [WebView.post] — the same pattern used for auth injection.
     */
    private fun parseThemeMessage(json: JSONObject) {
        val mode = json.optString("mode").takeIf { it.isNotBlank() }
        val accent = json.optString("accent").takeIf { it.isNotBlank() }
        if (mode == null && accent == null) return

        val wv = webView ?: return
        val context = wv.context ?: return
        wv.post {
            ThemePrefs.setFromWeb(context, mode, accent)
        }
    }

    /**
     * Web → native: { type: "kv", action: "set"|"remove", key, value } from the web's
     * `deviceStore`. Persists the verbatim pair so it can be re-seeded on the next launch.
     * `key` is the full localStorage key; [DeviceKvStore] guards that it is within the
     * `cw-kv:` namespace. Hops to the WebView thread for consistent context access.
     */
    private fun parseKvMessage(json: JSONObject) {
        val key = json.optString("key").takeIf { it.isNotBlank() } ?: return
        val action = json.optString("action").ifBlank { "set" }

        val wv = webView ?: return
        val context = wv.context ?: return
        wv.post {
            when (action) {
                "remove" -> DeviceKvStore.remove(context, key)
                else -> if (json.has("value")) DeviceKvStore.set(context, key, json.optString("value"))
            }
        }
    }

    private fun parseSystemMessage(json: JSONObject) {
        val eventName = json.optString("eventName")
        CWLog.log("Bridge system event: $eventName", category = "Bridge")

        when (eventName) {
            "api-ready" -> finalizeLoad()
            "app-ready" -> onAppReady.invoke(Unit)
            "logout" -> {
                CoroutineScope(Dispatchers.Main).launch {
                    ServiceManager.getService<AuthService>()?.signOut()
                }
            }
            "request-logs" -> {
                val requestId = if (json.has("requestId")) json.optInt("requestId") else null
                sendLogs(requestId)
            }
            "request-push-token" -> requestPushToken()
            "request-push-status" -> reportPushStatus()
            "open-push-settings" -> openPushSettings()
            "set-endpoint" -> setEndpoint(json.optString("endpoint"))
        }
    }

    /**
     * Web → native: `{ type: "system", eventName: "set-endpoint", endpoint }` —
     * an admin re-pointing the app at the production or the development site.
     *
     * What arrives is a channel NAME, and it is resolved through [EndpointStore]'s
     * allowlist; the two addresses never cross the bridge. That is what makes this
     * safe to expose on `window`: the worst a hostile script in the page can do is
     * send the user to the other site of ours.
     *
     * This callback runs on a binder thread, so it hops to the WebView's thread
     * before touching preferences and the Activity — the pattern used by the theme
     * and KV handlers above.
     */
    private fun setEndpoint(name: String?) {
        val endpoint = EndpointStore.endpointNamed(name?.takeIf { it.isNotBlank() })
        if (endpoint == null) {
            CWLog.log("Ignoring set-endpoint for an unknown endpoint", category = "Bridge")
            return
        }
        val view = webView ?: return
        view.post {
            val context = view.context ?: return@post
            if (!EndpointStore.set(context, endpoint)) return@post
            onEndpointChanged.invoke(endpoint)
        }
    }

    /**
     * Web → native: what is the OS notification state right now?
     *
     * Reads it rather than requesting anything — this is the settings screen
     * asking, not the app asking for access, so no prompt may appear.
     */
    private fun reportPushStatus() {
        val view = webView ?: return
        view.post {
            val service = ServiceManager.getService<PushService>()
            val context = view.context ?: return@post
            // A shell without the service can't answer; staying silent is
            // correct — the web side times out and shows nothing rather than
            // claiming notifications are off.
            val permission = service?.readPermission(context.applicationContext) ?: return@post
            pushStatus(permission)
        }
    }

    /** Web → native: take the user to this app's notification settings. */
    private fun openPushSettings() {
        val view = webView ?: return
        view.post {
            var context = view.context
            while (context is ContextWrapper && context !is Activity) {
                context = context.baseContext
            }
            ServiceManager.getService<PushService>()?.openSystemSettings(context ?: return@post)
        }
    }

    /**
     * Web → native: the app is signed in and wants this device's push token.
     *
     * The Android 13+ permission dialog needs a live Activity, and this callback
     * arrives on a binder thread, so it hops to the WebView's thread and unwraps
     * the Activity from its context.
     */
    private fun requestPushToken() {
        val view = webView ?: return
        view.post {
            var context = view.context
            while (context is ContextWrapper && context !is Activity) {
                context = context.baseContext
            }
            ServiceManager.getService<PushService>()?.requestRegistration(context as? Activity)
        }
    }

    /**
     * Answers a web `request-logs` event by reading this app's recent logcat
     * output (off the main thread) and calling `window.__capital_wizard.logs({...})`
     * in the WebView.
     */
    private fun sendLogs(requestId: Int?) {
        val wv = webView ?: return
        Thread {
            // Structured ring buffer is the reliable source; raw logcat is best-effort
            // extra detail (may be empty on ROMs that block self-log reads).
            val lines = ArrayList<String>()
            lines.addAll(CWLog.snapshot())
            val logcat = CWLog.readRecentLogcat()
            if (logcat.isNotEmpty()) {
                lines.add("──── logcat (raw) ────")
                lines.addAll(logcat)
            }
            CWLog.log("Returning ${lines.size} native log line(s) to web", category = "Bridge")
            val payload = JSONObject().apply {
                if (requestId != null) put("requestId", requestId)
                put("platform", "android")
                put("lines", JSONArray(lines))
            }
            val js = "window.__capital_wizard && window.__capital_wizard.logs && window.__capital_wizard.logs($payload);"
            wv.post { wv.evaluateJavascript(js, null) }
        }.start()
    }

    private fun finalizeLoad() {
        isReady = true
        val authService = ServiceManager.getService<AuthService>()
        val accessToken = authService?.getAccessToken() ?: return
        val refreshToken = authService.getRefreshToken() ?: return
        webView?.post {
            injectAuthScript(accessToken, refreshToken)
        }
    }
}
