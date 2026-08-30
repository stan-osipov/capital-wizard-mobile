package com.capitalwizard.android.ui.auth

import android.content.Intent
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
import com.capitalwizard.android.ui.SplashStatus
import com.capitalwizard.android.ui.WebViewActivity
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import kotlinx.coroutines.launch

class LoginActivity : AuthActivity() {

    private lateinit var binding: ActivityLoginBinding
    private var authService: AuthService? = null

    private val onLoginCallback = EventCallback<Unit> { navigateToMain() }

    /**
     * Set when a first run hands straight over to Create Account. This activity
     * then never revealed its own form, so coming BACK to it has to.
     */
    private var handedOffToSignUp = false

    /** 4-step dots cycle under the splash caption, matching WebViewActivity. */
    private var dotsStep = 0
    private val dotsTick = object : Runnable {
        override fun run() {
            dotsStep = (dotsStep + 1) % 4
            binding.splashView.splashDots.text = "\u00b7".repeat(dotsStep)
            binding.splashView.splashDots.postDelayed(this, 350L)
        }
    }

    /**
     * Takes the launch splash down.
     *
     * Every path out of the session check calls this — the form appearing, the
     * hand-off to Create Account, and the jump to the WebView — because the
     * splash covers the whole activity and whatever is revealed underneath is
     * invisible until it goes.
     */
    private fun stopSplashWork() {
        binding.splashView.root.removeCallbacks(dotsTick)
        binding.splashView.splashDots.removeCallbacks(dotsTick)
        SplashStatus.bind(null)
    }

    /**
     * Fades the splash away to reveal what is UNDERNEATH it — this activity's
     * own login form, and nothing else.
     *
     * Leaving for another activity must NOT use this. Both of those (the WebView
     * and Create Account) draw their own full screen, so fading here would
     * dissolve toward the empty form for a moment first; and the WebView puts up
     * this very same splash, so the honest handover is to leave ours painted and
     * let it be replaced. See [stopSplashWork].
     */
    private fun hideSplash() {
        val splash = binding.splashView.root
        if (splash.visibility != View.VISIBLE) return
        stopSplashWork()
        splash.animate().alpha(0f).setDuration(220).withEndAction {
            splash.visibility = View.GONE
        }.start()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // installSplashScreen() is still what swaps the splash theme out for the
        // app's own (`postSplashScreenTheme`), so it stays.
        //
        // What is deliberately GONE is `setKeepOnScreenCondition { isCheckingSession }`.
        // It held the SYSTEM splash window for the whole 1.5s session check, and
        // that window can only show a static drawable — which is why the mark was
        // stuck in one fixed amber no matter what accent somebody picked. Worse,
        // it sat ON TOP of this activity, so the app's own accent-coloured splash
        // was underneath it the entire time and only got its turn at the exact
        // moment the check finished and dismissed it.
        //
        // Letting the system window go at first draw hands the wait to
        // `include_splash` below, which is a real view and can read the accent.
        installSplashScreen()

        super.onCreate(savedInstanceState)

        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        applyInsets(binding.root)

        // The launch splash is what the user actually looks at for the next
        // 1.5s: the OS window behind it now carries only a themed background,
        // because its icon could never follow the chosen accent. SplashWView
        // can, so the mark here is the right colour from the first frame.
        SplashStatus.post("Restoring session…")
        SplashStatus.bind { text -> binding.splashView.splashStatus.text = text }
        binding.splashView.splashDots.postDelayed(dotsTick, 350L)

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
            if (authService?.isLoggedIn != true) {
                showLoginForm()
            }
        }, 1500)

        setupListeners()
    }

    override fun onResume() {
        super.onResume()
        // Back from the sign-up screen — "Log in here", or the system back
        // gesture. onCreate handed over before revealing anything, so without
        // this the person returns to a blank screen.
        //
        // Reveal the form DIRECTLY, and leave the latch SET. showLoginForm()
        // answers a different question - which screen this device STARTS on -
        // and it hands off to Create Account for as long as nobody has ever
        // signed in here, which is still true of somebody who has just walked
        // back from it. Clearing the latch and calling it again re-armed the
        // very condition the hand-off had already satisfied, so "I already
        // have an account" slid straight back to the screen it came from.
        // The hand-off is a once-per-launch event, not a toggle.
        if (handedOffToSignUp && authService?.isLoggedIn != true) {
            hideSplash()
            fadeIn(binding.loginForm)
        }
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
        // STASHED, not opened here: this runs inside onCreate, and navigateToMain()
        // below starts WebViewActivity milliseconds later, which would come to the
        // front and cover the browser we just launched. PushService holds it until
        // something is actually on screen to show it, exactly as a route is held in
        // DeepLinkService. The https re-check lives in recordExternalUrl.
        intent?.getStringExtra(PushMessagingService.EXTRA_URL)?.let { link ->
            if (link.isNotBlank()) {
                ServiceManager.getService<PushService>()?.recordExternalUrl(link)
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

    /**
     * Reveals the auth screen this device should START on.
     *
     * This activity stays the launcher — it owns the app-link and OAuth intent
     * filters, so the entry point cannot move — but on a device where nobody has
     * ever signed in it hands straight over to Create Account. A freshly
     * installed app has, by definition, no account here: the login form asks for
     * a password nobody has chosen yet and buries the way to register in a link
     * at the bottom. Create Account is also the screen carrying the referral
     * field, which is the whole point on a phone.
     *
     * `SignUpActivity` finishes back onto this one, so Login stays one tap away
     * and a sign-OUT lands here directly (the latch is set by then).
     * Mirrors iOS `WindowsService.showAuth()`.
     */
    private fun showLoginForm() {
        if (!handedOffToSignUp && authService?.hasEverSignedIn == false) {
            handedOffToSignUp = true
            // A dissolve rather than a slide: the login form has not been faded
            // in yet, so sliding would carry an empty version of this screen
            // past. Both screens share the auth chrome, so a crossfade reads as
            // the content changing rather than as a navigation.
            startActivity(Intent(this, SignUpActivity::class.java))
            setExitTransition(R.anim.cw_fade_in, R.anim.cw_fade_out)
            // No `finish()`: this activity is what SignUpActivity comes back to,
            // and onResume() fades the splash away then. Deliberately NOT faded
            // here: the transition above is suppressed, so a fade would show
            // this activity's empty form for a frame on the way out.
            stopSplashWork()
            return
        }
        hideSplash()
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
        // WebViewActivity raises the SAME splash (both use @layout/include_splash),
        // so ours stays painted right up to the swap and the two are
        // indistinguishable. Only the caption's timers stop — left running they
        // would tick against a view belonging to a finished activity.
        stopSplashWork()
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
        // A CROSSFADE, not the default slide and not a hard cut.
        //
        // The slide was plainly wrong — one copy of the splash sliding over
        // another. A hard cut is only invisible if the two land on identical
        // pixels, and they do not: this screen insets its root for the status
        // bar, the WebView does not, so the mark sits a few dp apart and the
        // swap read as a jump. Dissolving two near-identical screens into each
        // other costs 220ms and is robust to that difference instead of
        // depending on its absence.
        setExitTransition(R.anim.cw_fade_in, R.anim.cw_fade_out)
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogin?.unsubscribe(onLoginCallback)
        binding.splashView.splashDots.removeCallbacks(dotsTick)
        // The listener closes over a view, and so over this Activity.
        SplashStatus.bind(null)
    }
}
