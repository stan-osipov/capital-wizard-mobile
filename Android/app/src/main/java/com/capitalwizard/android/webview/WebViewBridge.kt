package com.capitalwizard.android.webview

import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.utils.Event
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.utils.ThemePrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

class WebViewBridge {

    val onAppReady = Event<Unit>()

    var webView: WebView? = null
    var isReady: Boolean = false
        private set

    companion object {
        const val JS_INTERFACE_NAME = "androidCW"
        const val BASE_URL = "https://capital-wizard.com/"
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

    fun getNativeAppScript(): String = """
        window.__capital_wizard_native = { platform: 'android' };
        document.documentElement.classList.add('cw-native-android');
    """.trimIndent()

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

    private fun parseSystemMessage(json: JSONObject) {
        val eventName = json.optString("eventName")

        when (eventName) {
            "api-ready" -> finalizeLoad()
            "app-ready" -> onAppReady.invoke(Unit)
            "logout" -> {
                CoroutineScope(Dispatchers.Main).launch {
                    ServiceManager.getService<AuthService>()?.signOut()
                }
            }
        }
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
