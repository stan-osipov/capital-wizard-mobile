package com.capitalwizard.android.ui

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
import androidx.lifecycle.lifecycleScope
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.capitalwizard.android.R
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.ui.auth.LoginActivity
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.webview.WebViewBridge
import kotlinx.coroutines.launch

class WebViewActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var splashView: View
    private lateinit var bridge: WebViewBridge

    private var authService: AuthService? = null

    private val onLogoutCallback = EventCallback<Unit> { navigateToLogin() }
    private val onAppReadyCallback = EventCallback<Unit> { runOnUiThread { revealWebView() } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_webview)

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
        swipeRefresh = findViewById(R.id.swipe_refresh)
        webView = findViewById(R.id.web_view)

        setupWebView()
        loadApp()

        swipeRefresh.setOnRefreshListener {
            webView.reload()
        }

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

        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.addJavascriptInterface(bridge, WebViewBridge.JS_INTERFACE_NAME)
        bridge.webView = webView

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                swipeRefresh.isRefreshing = false

                // Inject native app identifier script
                view?.evaluateJavascript(bridge.getNativeAppScript(), null)
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
            ): Boolean {
                // Recreate the WebView if the renderer crashes
                bridge.clearState()
                recreate()
                return true
            }
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
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            super.onPageFinished(view, url)
                            swipeRefresh.isRefreshing = false

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
                        ): Boolean {
                            bridge.clearState()
                            recreate()
                            return true
                        }
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

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogout?.unsubscribe(onLogoutCallback)
        bridge.onAppReady -= onAppReadyCallback
        bridge.webView = null
        webView.destroy()
    }
}
