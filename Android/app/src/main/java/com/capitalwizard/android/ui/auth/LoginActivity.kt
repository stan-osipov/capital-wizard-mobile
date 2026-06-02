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
        val uri = intent?.data ?: return
        if (uri.scheme == "capital-wizard-android") {
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
        startActivity(Intent(this, WebViewActivity::class.java))
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogin?.unsubscribe(onLoginCallback)
    }
}
