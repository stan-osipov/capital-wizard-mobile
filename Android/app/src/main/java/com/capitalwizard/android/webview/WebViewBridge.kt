package com.capitalwizard.android.webview

import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.utils.Event
import com.capitalwizard.android.utils.ServiceManager
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
                "auth" -> { /* reserved */ }
            }
        } catch (e: Exception) {
            e.printStackTrace()
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
