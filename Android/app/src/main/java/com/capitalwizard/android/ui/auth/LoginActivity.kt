package com.capitalwizard.android.ui.auth

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.capitalwizard.android.R
import com.capitalwizard.android.databinding.ActivityLoginBinding
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.services.DeepLinkService
import com.capitalwizard.android.services.PushMessagingService
import com.capitalwizard.android.services.PushService
import com.capitalwizard.android.ui.WebViewActivity
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import kotlinx.coroutines.launch

class LoginActivity : AuthActivity() {

    private lateinit var binding: ActivityLoginBinding
    private var authService: AuthService? = null

    private val onLoginCallback = EventCallback<Unit> { navigateToMain() }

    private var isCheckingSession = true

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { isCheckingSession }

        super.onCreate(savedInstanceState)

        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        applyInsets(binding.root)
        setupLocalePill(binding.appBar.btnLanguage)
        setupLegalFooter(binding.legalFooter)

        authService = ServiceManager.getService<AuthService>()
        authService?.onLogin?.subscribe(onLoginCallback)

        // Handle OAuth deep link
        handleIntent(intent)

        // Try restoring existing session
        authService?.tryRestoreSession()

        // If already logged in, navigate immediately
        if (authService?.isLoggedIn == true) {
            navigateToMain()
            return
        }

        // Give session restore a moment, then show login UI
        binding.root.postDelayed({
            isCheckingSession = false
            if (authService?.isLoggedIn != true) {
                showLoginForm()
            }
        }, 1500)

        setupListeners()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        // A tapped notification announces its click-tracking id here — both the
        // system-tray tap (FCM copies data keys onto the launcher intent) and
        // our own foreground notification funnel through this activity. The id
        // is stashed like a deep link; the web app reports it once it is up.
        intent?.getStringExtra(PushMessagingService.EXTRA_SEND_ID)?.let { sendId ->
            if (sendId.isNotBlank()) {
                ServiceManager.getService<PushService>()?.reportOpen(sendId)
            }
        }

        // A tapped push notification carries its route as an extra rather than as
        // intent data — same stash, so WebViewActivity picks it up from
        // DeepLinkService exactly as it would a link.
        intent?.getStringExtra(PushMessagingService.EXTRA_ROUTE)?.let { route ->
            if (route.isNotBlank()) {
                ServiceManager.getService<DeepLinkService>()?.handleRoutePath(route)
            }
        }

        // An external page goes to the browser, never into the app's own WebView
        // — that WebView is signed in, and an outside origin must not run there.
        // https is re-checked even though the server enforced it: this value
        // arrived over the network, and an ACTION_VIEW on an arbitrary scheme is
        // a way to launch other apps.
        intent?.getStringExtra(PushMessagingService.EXTRA_URL)?.let { link ->
            val external = runCatching { Uri.parse(link) }.getOrNull()
            if (external?.scheme?.lowercase() == "https") {
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, external)) }
            }
        }

        val uri = intent?.data ?: return

        // Routing links and the OAuth callback share the custom scheme, split by
        // host (`open` vs `auth`). Offer it to the router first; anything it
        // declines is the auth leg and still reaches AuthService untouched. The
        // route itself is stashed in DeepLinkService rather than passed along —
        // WebViewActivity picks it up from there once it can show it.
        val deepLinkService = ServiceManager.getService<DeepLinkService>()
        if (deepLinkService?.handle(uri) == true) return

        if (uri.scheme == DeepLinkService.CUSTOM_SCHEME) {
            authService?.handleDeepLink(uri)
        }
    }

    private fun showLoginForm() {
        fadeIn(binding.loginForm)
    }

    private fun setupListeners() {
        binding.btnSignIn.setOnClickListener {
            val email = binding.inputEmail.text.toString().trim()
            val password = binding.inputPassword.text.toString().trim()

            if (email.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, R.string.error_empty_fields, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            setLoading(true)
            lifecycleScope.launch {
                try {
                    authService?.signIn(email, password)
                } catch (e: Exception) {
                    setLoading(false)
                    Toast.makeText(
                        this@LoginActivity,
                        e.message ?: getString(R.string.error_sign_in),
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        binding.btnGoogleSignIn.setOnClickListener {
            setLoading(true)
            lifecycleScope.launch {
                try {
                    authService?.signInWithGoogle()
                } catch (e: Exception) {
                    setLoading(false)
                    Toast.makeText(
                        this@LoginActivity,
                        e.message ?: getString(R.string.error_sign_in),
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        binding.btnForgotPassword.setOnClickListener {
            startActivity(Intent(this, ResetPasswordActivity::class.java))
        }

        binding.btnSignUp.setOnClickListener {
            startActivity(Intent(this, SignUpActivity::class.java))
        }
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnSignIn.isEnabled = !loading
        binding.btnGoogleSignIn.isEnabled = !loading
        binding.btnSignUp.isEnabled = !loading
        binding.btnForgotPassword.isEnabled = !loading
    }

    private fun navigateToMain() {
        isCheckingSession = false
        // Reuse a WebViewActivity that is already running rather than stacking a
        // second one. A deep link arriving while the app is backgrounded re-enters
        // through this Activity, so without these flags every link would leave
        // another WebView behind on the back stack. CLEAR_TOP + SINGLE_TOP hands
        // the existing instance an onNewIntent instead, which is also what lets it
        // route the link in place instead of reloading.
        val intent = Intent(this, WebViewActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogin?.unsubscribe(onLoginCallback)
    }
}
