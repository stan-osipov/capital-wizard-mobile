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
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.capitalwizard.android.R
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.services.DeepLinkService
import com.capitalwizard.android.services.PushRegistration
import com.capitalwizard.android.services.PushService
import com.capitalwizard.android.ui.auth.LoginActivity
import com.capitalwizard.android.utils.AppEndpoint
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.webview.WebViewBridge
import kotlinx.coroutines.launch

class WebViewActivity : AppCompatActivity() {

    companion object {
        /**
         * The web app posts to `window.webkit.messageHandlers.iosCW` (iOS) or
         * `window.androidCW` (Android). We stand the iOS-shaped path up too, so
         * anything written against it works here without a platform branch.
         */
        private val IOS_BRIDGE_SHIM = """
            (function () {
                if (!window.webkit) { window.webkit = {}; }
                if (!window.webkit.messageHandlers) { window.webkit.messageHandlers = {}; }
                if (!window.webkit.messageHandlers.iosCW) {
                    window.webkit.messageHandlers.iosCW = {
                        postMessage: function (msg) {
                            window.${WebViewBridge.JS_INTERFACE_NAME}.postMessage(JSON.stringify(msg));
                        }
                    };
                }
            })();
        """.trimIndent()
    }

    private lateinit var webView: WebView
    private lateinit var splashView: View
    private lateinit var bridge: WebViewBridge

    private var authService: AuthService? = null
    private var deepLinkService: DeepLinkService? = null
    private var pushService: PushService? = null

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

    /** True once the document-start scripts are registered. When false this
     *  WebView is too old for them and the client callbacks inject instead. */
    private var documentStartInstalled = false

    private val onLogoutCallback = EventCallback<Unit> { navigateToLogin() }
    private val onAppReadyCallback = EventCallback<Unit> {
        runOnUiThread {
            revealWebView()
            // The web app is signed in and rendering, so taps stashed through a
            // cold launch can finally be reported.
            flushOpenReports()
        }
    }
    private val onDeepLinkCallback = EventCallback<String> { runOnUiThread { routePendingDeepLink() } }

    /** An admin switched the endpoint from inside the web app. The new address is
     *  already persisted; restarting the Activity is what moves us onto it — a
     *  plain reload would re-fetch the OLD url and would also keep the injected
     *  script that told the page which site it was on. */
    private val onEndpointChangedCallback = EventCallback<AppEndpoint> { endpoint ->
        runOnUiThread {
            CWLog.log("Endpoint changed to ${endpoint.channel} — restarting the web layer", category = "WebView")
            recreateOnce()
        }
    }

    /** FCM answered the web app's token request — hand it straight over. */
    private val onPushRegistrationCallback = EventCallback<PushRegistration?> { registration ->
        runOnUiThread { bridge.pushRegistration(registration, pushService?.lastFailureReason) }
    }

    /** A warm tap recorded its click-tracking id — forward it if the bridge is
     *  live; otherwise it stays stashed for the app-ready flush above. */
    private val onOpenRecordedCallback = EventCallback<Unit> {
        runOnUiThread { if (bridge.isReady) flushOpenReports() }
    }

    /** Hands the stashed tap ids to the web app. Consuming clears the stash, so
     *  a failed push puts nothing back — dropping a best-effort statistic beats
     *  machinery to retry it. */
    private fun flushOpenReports() {
        val ids = pushService?.consumePendingOpenReports() ?: return
        if (ids.isNotEmpty()) bridge.pushOpened(ids)
    }

    /** Back walks the WebView's history while it has any; disabled, the system
     *  takes over (backgrounding the task, with the predictive animation on 16+).
     *  Targeting SDK 36, Android 16 no longer calls a legacy onBackPressed()
     *  override, so the enabled flag — kept fresh by doUpdateVisitedHistory on
     *  both WebViewClients — is what declares whether we consume Back. */
    private val webBackCallback = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() {
            webView.goBack()
        }
    }

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

        deepLinkService = ServiceManager.getService<DeepLinkService>()
        pushService = ServiceManager.getService<PushService>()
        pushService?.onRegistration?.subscribe(onPushRegistrationCallback)
        pushService?.onOpenRecorded?.subscribe(onOpenRecordedCallback)

        bridge = WebViewBridge()
        bridge.onAppReady += onAppReadyCallback
        bridge.onEndpointChanged += onEndpointChangedCallback

        splashView = findViewById(R.id.splash_view)
        webView = findViewById(R.id.web_view)

        onBackPressedDispatcher.addCallback(this, webBackCallback)

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
                // Fallback for WebView < 83 only — see installDocumentStartScripts.
                // This races the page's own scripts, which is why it is the fallback:
                // the pre-paint script may read the theme before the seed lands.
                if (documentStartInstalled) return
                view?.evaluateJavascript(bridge.getNativeAppScript(), null)
                val seed = bridge.getThemeSeedScript()
                if (seed.isNotEmpty()) view?.evaluateJavascript(seed, null)
                val kvSeed = bridge.getKvSeedScript()
                if (kvSeed.isNotEmpty()) view?.evaluateJavascript(kvSeed, null)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                CWLog.log("Page finished loading", category = "WebView")

                // Belt and braces on the fallback path: the web app reads
                // `__capital_wizard_native` at module scope, and losing that race
                // costs it `app-ready` — which strands the splash on its timeout.
                // Idempotent, so re-running it here is free.
                if (!documentStartInstalled) {
                    view?.evaluateJavascript(bridge.getNativeAppScript(), null)
                }

                view?.evaluateJavascript(IOS_BRIDGE_SHIM, null)
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
                val baseHost = Uri.parse(WebViewBridge.baseUrl(this@WebViewActivity)).host

                // Open external links in the system browser
                return if (url.host != baseHost) {
                    startActivity(Intent(Intent.ACTION_VIEW, url))
                    true
                } else {
                    false
                }
            }

            override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                super.doUpdateVisitedHistory(view, url, isReload)
                webBackCallback.isEnabled = view?.canGoBack() == true
            }

            override fun onRenderProcessGone(
                view: WebView?,
                detail: android.webkit.RenderProcessGoneDetail?
            ): Boolean = handleRenderProcessGone(detail)
        }

        webView.webChromeClient = WebChromeClient()
    }

    /**
     * Registers everything the page must see BEFORE its own scripts run.
     *
     * `evaluateJavascript` cannot do this. It acts on the document loaded RIGHT
     * NOW, and the `loadUrl` that follows replaces that document — taking the
     * injection with it. `addDocumentStartJavaScript` registers against the
     * WebView instead, so each script runs at the start of every matching load.
     * This is the Android expression of the iOS shell's `WKUserScript` list.
     *
     * Carrying the SESSION here is what matters most: the web app wakes its
     * services exactly once, and a session that arrives after that leaves it
     * signed-out for the life of the document — a shell with no space and no
     * active app, which is the blank screen the first Google sign-in produced.
     *
     * Unsupported on WebView < 83 (`DOCUMENT_START_SCRIPT`). There the page
     * still gets these values from the client callbacks above, and the session
     * still lands through the `api-ready` handshake — the web app then reloads
     * once into it, which is slower but correct.
     */
    private fun installDocumentStartScripts(accessToken: String?, refreshToken: String?) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            CWLog.log(
                "Document-start scripts unsupported — using page-callback fallback",
                category = "WebView",
            )
            return
        }

        // Scoped to our own origin: these scripts carry this device's session.
        val rules = setOf(WebViewBridge.originRule(this))

        val scripts = buildList {
            add(bridge.getNativeAppScript())
            add(IOS_BRIDGE_SHIM)
            bridge.getThemeSeedScript().takeIf { it.isNotEmpty() }?.let { add(it) }
            bridge.getKvSeedScript().takeIf { it.isNotEmpty() }?.let { add(it) }
            if (accessToken != null && refreshToken != null) {
                add(bridge.getAuthSeedScript(accessToken, refreshToken))
            }
        }

        // An origin rule the WebView rejects throws rather than returning null,
        // and failing to inject must not take the whole load down with it — the
        // fallback path still gets the user to a working app.
        val installed = scripts.all { script ->
            runCatching { WebViewCompat.addDocumentStartJavaScript(webView, script, rules) }
                .onFailure {
                    CWLog.log("Document-start script rejected: ${it.message}", category = "WebView")
                }
                .isSuccess
        }

        documentStartInstalled = installed
        CWLog.log(
            "Document-start scripts installed=$installed (auth=${accessToken != null})",
            category = "WebView",
        )
    }

    private fun loadApp() {
        lifecycleScope.launch {
            val accessToken = authService?.getAccessToken()
            val refreshToken = authService?.getRefreshToken()

            // Registered against the WebView, so — unlike an evaluateJavascript
            // call — these survive the loadUrl below and run before the page's
            // own scripts on every load.
            installDocumentStartScripts(accessToken, refreshToken)

            val startUrl = buildStartUrl()
            CWLog.log("Loading URL: $startUrl (auth=${accessToken != null})", category = "WebView")
            webView.loadUrl(startUrl)

            // Start listening for live links only now. Subscribing earlier would
            // race this coroutine: a link landing before buildStartUrl() ran would
            // be routed and then immediately overwritten by the initial load.
            deepLinkService?.onDeepLink?.subscribe(onDeepLinkCallback)
        }
    }

    /**
     * The first URL to load. A link stashed before this WebView existed — a cold
     * start, or one that sat through the sign-in gate — becomes the very first URL,
     * so the user lands on it directly instead of watching the root redirect.
     * [DeepLinkService.consumePendingPath] clears it, so a later reload (the
     * resume-from-background recovery, say) won't silently repeat the navigation.
     */
    private fun buildStartUrl(): String {
        val base = WebViewBridge.baseUrl(this)
        val path = deepLinkService?.consumePendingPath() ?: return base
        // Both sides carry a slash: the base URL ends with one, the route starts with one.
        return base + path.removePrefix("/")
    }

    /**
     * Shows a link that arrived while this WebView was already alive. Prefers an
     * in-place route through the bridge — that keeps the session and skips a full
     * reload — and falls back to loading the URL outright if the bridge isn't up.
     */
    private fun routePendingDeepLink() {
        val path = deepLinkService?.consumePendingPath() ?: return

        if (bridge.isReady && bridge.pushNavigate(path)) {
            CWLog.log("Routed $path in place", category = "DeepLink")
            return
        }

        CWLog.log("Bridge not ready — routing $path via a full load", category = "DeepLink")
        webView.loadUrl(WebViewBridge.baseUrl(this) + path.removePrefix("/"))
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

    /**
     * Re-entry with a link. LoginActivity is the app's front door, so a link tapped
     * while the app is backgrounded lands there first and comes back here via
     * CLEAR_TOP + SINGLE_TOP — carrying no data of its own, because the route was
     * already stashed in [DeepLinkService]. A VIEW intent delivered straight to this
     * Activity is covered too: [DeepLinkService.handle] is a no-op when there is
     * nothing routable to read.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkService?.handle(intent.data)
        routePendingDeepLink()
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
                // Left as-is is right for the PAGE and wrong for anything on it
                // describing the world outside the app. Tell the web app it is
                // back so those screens can re-read; it decides what is worth
                // refreshing, which is why this is a ping and not a reload.
                bridge.pushForeground()
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

    /**
     * The Android 13+ notification prompt is raised by PushService but answered
     * here — permission results only ever reach the Activity that asked.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PushService.PERMISSION_REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        pushService?.onPermissionResult(this, granted)
    }

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogout?.unsubscribe(onLogoutCallback)
        deepLinkService?.onDeepLink?.unsubscribe(onDeepLinkCallback)
        pushService?.onRegistration?.unsubscribe(onPushRegistrationCallback)
        pushService?.onOpenRecorded?.unsubscribe(onOpenRecordedCallback)
        bridge.onAppReady -= onAppReadyCallback
        bridge.webView = null
        webView.destroy()
    }
}
