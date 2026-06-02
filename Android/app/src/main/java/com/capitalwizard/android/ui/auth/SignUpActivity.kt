package com.capitalwizard.android.ui.auth

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.capitalwizard.android.R
import com.capitalwizard.android.databinding.ActivitySignUpBinding
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.ui.WebViewActivity
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import kotlinx.coroutines.launch

class SignUpActivity : AuthActivity() {

    private lateinit var binding: ActivitySignUpBinding
    private var authService: AuthService? = null

    private val onLoginCallback = EventCallback<Unit> { navigateToMain() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivitySignUpBinding.inflate(layoutInflater)
        setContentView(binding.root)

        applyInsets(binding.root)
        setupLocalePill(binding.appBar.btnLanguage)
        setupLegalFooter(binding.legalFooter)
        linkifyTermsAndPrivacy(binding.termsAgreeText, getString(R.string.signup_terms_agree))

        authService = ServiceManager.getService<AuthService>()
        authService?.onLogin?.subscribe(onLoginCallback)

        // Primary button is gated by the terms checkbox.
        binding.btnCreateAccount.isEnabled = binding.checkboxTerms.isChecked
        binding.checkboxTerms.setOnCheckedChangeListener { _, checked ->
            binding.btnCreateAccount.isEnabled = checked
        }

        setupListeners()
    }

    private fun setupListeners() {
        binding.btnCreateAccount.setOnClickListener {
            val email = binding.inputEmail.text.toString().trim()
            val password = binding.inputPassword.text.toString().trim()
            val confirm = binding.inputConfirmPassword.text.toString().trim()

            if (email.isEmpty() || password.isEmpty() || confirm.isEmpty()) {
                Toast.makeText(this, R.string.error_empty_fields, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (password.length < 8) {
                Toast.makeText(this, R.string.error_password_short, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (password != confirm) {
                Toast.makeText(this, R.string.error_passwords_mismatch, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (!binding.checkboxTerms.isChecked) {
                Toast.makeText(this, R.string.error_terms_required, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            setLoading(true)
            lifecycleScope.launch {
                try {
                    // true → auto-logged-in (onLogin fires → navigateToMain).
                    // false → email confirmation required → show confirmation state.
                    val success = authService?.signUp(email, password) ?: false
                    setLoading(false)
                    if (!success) {
                        showConfirmationState()
                    }
                } catch (e: Exception) {
                    setLoading(false)
                    Toast.makeText(
                        this@SignUpActivity,
                        e.message ?: getString(R.string.error_sign_up),
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        binding.btnGoogleSignUp.setOnClickListener {
            setLoading(true)
            lifecycleScope.launch {
                try {
                    authService?.signInWithGoogle()
                } catch (e: Exception) {
                    setLoading(false)
                    Toast.makeText(
                        this@SignUpActivity,
                        e.message ?: getString(R.string.error_sign_up),
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        binding.btnBackToLogin.setOnClickListener { finish() }
        binding.btnConfirmBackToLogin.setOnClickListener { finish() }
    }

    private fun showConfirmationState() {
        binding.signupForm.visibility = View.GONE
        fadeIn(binding.confirmationView)
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnCreateAccount.isEnabled = !loading && binding.checkboxTerms.isChecked
        binding.btnGoogleSignUp.isEnabled = !loading
        binding.btnBackToLogin.isEnabled = !loading
    }

    private fun navigateToMain() {
        startActivity(Intent(this, WebViewActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        authService?.onLogin?.unsubscribe(onLoginCallback)
    }
}
