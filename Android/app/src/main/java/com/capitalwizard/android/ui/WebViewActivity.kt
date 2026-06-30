package com.capitalwizard.android.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import com.capitalwizard.android.R
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.ui.auth.LoginActivity
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.webview.WebViewBridge
import kotlinx.coroutines.launch

class WebViewActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var splashView: View
    private lateinit var bridge: WebViewBridge

    private var authService: AuthService? = null

    // --- Resume-from-background WebView recovery (mirrors the iOS shell) ---
    /** Elapsed-realtime millis when the app last entered the background. */
    private var backgroundedAt: Long = 0L
    /** True once a real background (onStop) happened — lets onResume ignore
     *  transient pauses (permission dialogs, etc.) where onStop never fired. */
    private var didBackground = false
    /** Set when the renderer died while backgrounded; consumed on next foreground. */
    private var pendingReload = false
    /** Guards against calling recreate() more than once on this Activity instance. */
    private var recreateScheduled = false

    private val onLogoutCallback = EventCallback<Unit> { navigateToLogin() }
    private val onAppReadyCallback = EventCallback<Unit> { runOnUiThread { revealWebView() } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_webview)
        CWLog.log("WebViewActivity created", category = "WebView")

        // Light status bar icons (white) for dark background
        WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = false

        // Edge-to-edge insets
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.root)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, 0, systemBars.right, 0)
            insets
        }

        authService = ServiceManager.getService<AuthService>()
        authService?.onLogout?.subscribe(onLogoutCallback)

        bridge = WebViewBridge()
        bridge.onAppReady += onAppReadyCallback

        splashView = findViewById(R.id.splash_view)
        webView = findViewById(R.id.web_view)

        setupWebView()
        loadApp()

        // Timeout fallback for splash
        splashView.postDelayed({ revealWebView() }, 15_000)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_DEFAULT
            setSupportMultipleWindows(false)
            useWideViewPort = true
            loadWithOverviewMode = true

            // Match iOS viewport behavior
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
        }

        // The web app is a fixed app shell with its own scroll containers — kill
        // the document-level overscroll glow (the WebView itself never scrolls).
        webView.overScrollMode = View.OVER_SCROLL_NEVER

        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.addJavascriptInterface(bridge, WebViewBridge.JS_INTERFACE_NAME)
        bridge.webView = webView

        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(
                view: WebView?,
                url: String?,
                favicon: android.graphics.Bitmap?
            ) {
                super.onPageStarted(view, url, favicon)
                // Seed saved theme/accent into localStorage BEFORE the page's inline
                // pre-paint script reads it (avoids a theme flash).
                val seed = bridge.getThemeSeedScript()
                if (seed.isNotEmpty()) view?.evaluateJavascript(seed, null)
                // Seed generic device-store values the same way.
                val kvSeed = bridge.getKvSeedScript()
                if (kvSeed.isNotEmpty()) view?.evaluateJavascript(kvSeed, null)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)

                // Inject native app identifier script
                view?.evaluateJavascript(bridge.getNativeAppScript(), null)

                // Fallback theme push in case the pre-paint seed landed late.
                val push = bridge.getThemePushScript()
                if (push.isNotEmpty()) view?.evaluateJavascript(push, null)
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val url = request?.url ?: return false
                val baseHost = Uri.parse(WebViewBridge.BASE_URL).host

                // Open external links in the system browser
                return if (url.host != baseHost) {
                    startActivity(Intent(Intent.ACTION_VIEW, url))
                    true
                } else {
                    false
                }
            }

            override fun onRenderProcessGone(
                view: WebView?,
                detail: android.webkit.RenderProcessGoneDetail?
            ): Boolean = handleRenderProcessGone(detail)
        }

        webView.webChromeClient = WebChromeClient()

        // Inject the JS bridge setup script that routes messages to our interface
        val setupScript = """
            (function() {
                ${bridge.getNativeAppScript()}

                // Create bridge: web app posts to window.webkit.messageHandlers.iosCW (iOS)
                // or window.androidCW (Android). We set up the iOS-compatible path too.
                if (!window.webkit) { window.webkit = {}; }
                if (!window.webkit.messageHandlers) { window.webkit.messageHandlers = {}; }
                if (!window.webkit.messageHandlers.iosCW) {
                    window.webkit.messageHandlers.iosCW = {
                        postMessage: function(msg) {
                            window.androidCW.postMessage(JSON.stringify(msg));
                        }
                    };
                }
            })();
        """.trimIndent()
        webView.evaluateJavascript(setupScript, null)
    }

    private fun loadApp() {
        // Inject auth tokens before loading
        lifecycleScope.launch {
            val accessToken = authService?.getAccessToken()
            val refreshToken = authService?.getRefreshToken()

            if (accessToken != null && refreshToken != null) {
                // Add auth injection script that runs at document end
                bridge.webView?.let { wv ->
                    wv.webViewClient = object : WebViewClient() {
                        override fun onPageStarted(
                            view: WebView?,
                            url: String?,
                            favicon: android.graphics.Bitmap?
                        ) {
                            super.onPageStarted(view, url, favicon)
                            // Inject native platform identifier early
                            view?.evaluateJavascript(bridge.getNativeAppScript(), null)
                            // Seed saved theme/accent into localStorage BEFORE the page's
                            // inline pre-paint script reads it (avoids a theme flash).
                            val seed = bridge.getThemeSeedScript()
                            if (seed.isNotEmpty()) view?.evaluateJavascript(seed, null)
                            // Seed generic device-store values the same way.
                            val kvSeed = bridge.getKvSeedScript()
                            if (kvSeed.isNotEmpty()) view?.evaluateJavascript(kvSeed, null)
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            super.onPageFinished(view, url)
                            CWLog.log("Page finished loading", category = "WebView")

                            // Inject the iOS-compatible bridge
                            val bridgeScript = """
                                (function() {
                                    if (!window.webkit) { window.webkit = {}; }
                                    if (!window.webkit.messageHandlers) { window.webkit.messageHandlers = {}; }
                                    if (!window.webkit.messageHandlers.iosCW) {
                                        window.webkit.messageHandlers.iosCW = {
                                            postMessage: function(msg) {
                                                window.androidCW.postMessage(JSON.stringify(msg));
                                            }
                                        };
                                    }
                                })();
                            """.trimIndent()
                            view?.evaluateJavascript(bridgeScript, null)

                            // Inject zoom disable
                            view?.evaluateJavascript(bridge.getZoomDisableScript(), null)

                            // Fallback theme push in case the pre-paint seed landed late:
                            // applies the saved theme/accent live via __capital_wizard.theme.
                            val push = bridge.getThemePushScript()
                            if (push.isNotEmpty()) view?.evaluateJavascript(push, null)
                        }

                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): Boolean {
                            val url = request?.url ?: return false
                            val baseHost = Uri.parse(WebViewBridge.BASE_URL).host
                            return if (url.host != baseHost) {
                                startActivity(Intent(Intent.ACTION_VIEW, url))
                                true
                            } else {
                                false
                            }
                        }

                        override fun onRenderProcessGone(
                            view: WebView?,
                            detail: android.webkit.RenderProcessGoneDetail?
                        ): Boolean = handleRenderProcessGone(detail)
                    }
                }

                // Pre-inject auth tokens as a script that will run on page load
                val authScript = """
                    (function() {
                        var _origAuth = null;
                        Object.defineProperty(window, '__capital_wizard', {
                            configurable: true,
                            set: function(v) { _origAuth = v; },
                            get: function() {
                                if (_origAuth) {
                                    // Once the real object is set, inject auth immediately
                                    try {
                                        _origAuth.auth({"auth_token":"$accessToken","refresh_token":"$refreshToken"}, '*');
                                    } catch(e) {}
                                }
                                return _origAuth;
                            }
                        });
                    })();
                """.trimIndent()
                webView.evaluateJavascript(authScript, null)
            }

            CWLog.log("Loading URL: ${WebViewBridge.BASE_URL} (auth=${accessToken != null})", category = "WebView")
            webView.loadUrl(WebViewBridge.BASE_URL)
        }
    }

    private fun revealWebView() {
        if (splashView.visibility != View.VISIBLE) return

        webView.alpha = 0f
        webView.scaleX = 0.96f
        webView.scaleY = 0.96f

        splashView.animate()
            .alpha(0f)
            .scaleX(1.08f)
            .scaleY(1.08f)
            .setDuration(500)
            .withEndAction { splashView.visibility = View.GONE }
            .start()

        webView.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setStartDelay(100)
            .setDuration(450)
            .start()
    }

    private fun navigateToLogin() {
        CWLog.log("Logout — clearing WebView data and navigating to login", category = "Auth")
        // Clear WebView data
        CookieManager.getInstance().removeAllCookies(null)
        webView.clearCache(true)
        webView.clearHistory()

        startActivity(Intent(this, LoginActivity::class.java))
        finish()
    }

    @Deprecated("Use onBackPressedDispatcher")
    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }

    override fun onStop() {
        super.onStop()
        didBackground = true
        backgroundedAt = SystemClock.elapsedRealtime()
        CWLog.log("Entered background", category = "WebView")
    }

    override fun onResume() {
        super.onResume()
        // Only react to a real return from the background (onStop fired) — ignore
        // transient pauses (e.g. permission dialogs) where onStop never happened.
        if (!didBackground) return
        didBackground = false

        // A (re)load is already in progress — its preloader is on screen. Don't
        // restart it here or the W animation visibly jumps back to the start. A
        // renderer that actually dies is still covered by handleRenderProcessGone.
        if (splashView.visibility == View.VISIBLE) {
            CWLog.log("Resumed while preloader showing — leaving load in progress", category = "WebView")
            return
        }

        val elapsed = SystemClock.elapsedRealtime() - backgroundedAt

        // Fast path: the renderer was reported dead while backgrounded — reload now.
        if (pendingReload) {
            pendingReload = false
            CWLog.log("Renderer terminated while backgrounded — reloading", category = "WebView")
            recreateOnce()
            return
        }

        // Otherwise PING the live web content and reload ONLY if it is unresponsive
        // (dead renderer) or blank (rendered nothing). A healthy app is left exactly
        // as it was — no needless reload, so the user is never bounced back through
        // the auth screen for an app that was actually fine.
        CWLog.log("Resumed after ${elapsed / 1000}s — pinging web content", category = "WebView")
        pingWebContent { healthy ->
            if (healthy) {
                CWLog.log("Health ping OK — WebView left as-is", category = "WebView")
            } else {
                CWLog.log("Health ping failed (unresponsive/blank) — reloading WebView", category = "WebView")
                recreateOnce()
            }
        }
    }

    /**
     * Probe whether the live web content is responsive and has actually rendered.
     * Calls back with `false` if the renderer is dead (evaluateJavascript yields
     * `"null"`) or the app rendered nothing into `#root` (a blank screen). Used on
     * foreground to decide whether a reload is genuinely needed, so a healthy app
     * is never reloaded. The callback runs on the UI thread.
     */
    private fun pingWebContent(callback: (Boolean) -> Unit) {
        val probe = "(function(){try{var r=document.getElementById('root');" +
            "return !!(window.__capital_wizard && r && r.childElementCount > 0);}" +
            "catch(e){return false;}})()"
        webView.evaluateJavascript(probe) { value ->
            // evaluateJavascript returns the JSON-encoded result: "true"/"false"/"null".
            callback(value == "true")
        }
    }

    /**
     * Handles [WebViewClient.onRenderProcessGone] — the renderer process was killed
     * (commonly under memory pressure while backgrounded), which leaves a blank
     * WebView. Rebuilds the Activity (fresh WebView + splash) immediately when
     * foreground; otherwise defers to [onResume] so we never reload while
     * backgrounded — that would stall the load and time the splash out onto a
     * blank view. Returning true tells the system we handled it (don't kill us).
     */
    private fun handleRenderProcessGone(detail: android.webkit.RenderProcessGoneDetail?): Boolean {
        val crashed = detail?.didCrash() == true
        CWLog.log("Render process gone (crashed=$crashed)", category = "WebView")
        bridge.clearState()
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            recreateOnce()
        } else {
            CWLog.log("Renderer gone while backgrounded — deferring reload to next foreground", category = "WebView")
            pendingReload = true
        }
        return true
    }

    /**
     * Calls [recreate] at most once per Activity instance, so two recovery triggers
     * firing close together (e.g. a stale resume and an onRenderProcessGone
     * callback) can't tear down and restart the preloader twice.
     */
    private fun recreateOnce() {
        if (recreateScheduled) return
        recreateScheduled = true
        CWLog.log("Recreating activity (fresh WebView + preloader)", category = "WebView")
        recreate()
    }

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogout?.unsubscribe(onLogoutCallback)
        bridge.onAppReady -= onAppReadyCallback
        bridge.webView = null
        webView.destroy()
    }
}
