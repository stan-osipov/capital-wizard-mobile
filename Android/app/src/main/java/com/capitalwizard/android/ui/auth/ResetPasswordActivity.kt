package com.capitalwizard.android.ui.auth

import android.os.Bundle
import android.util.Patterns
import android.view.View
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.capitalwizard.android.R
import com.capitalwizard.android.databinding.ActivityResetPasswordBinding
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.utils.ServiceManager
import kotlinx.coroutines.launch

class ResetPasswordActivity : AuthActivity() {

    private lateinit var binding: ActivityResetPasswordBinding
    private var authService: AuthService? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivityResetPasswordBinding.inflate(layoutInflater)
        setContentView(binding.root)

        applyInsets(binding.root)
        setupLocalePill(binding.appBar.btnLanguage)
        setupLegalFooter(binding.legalFooter)

        authService = ServiceManager.getService<AuthService>()

        setupListeners()
    }

    private fun setupListeners() {
        binding.btnSendReset.setOnClickListener {
            val email = binding.inputEmail.text.toString().trim()

            if (email.isEmpty()) {
                Toast.makeText(this, R.string.error_email_required, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (!Patterns.EMAIL_ADDRESS.matcher(email).matches()) {
                Toast.makeText(this, R.string.error_email_invalid, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            setLoading(true)
            lifecycleScope.launch {
                try {
                    authService?.resetPasswordForEmail(email)
                    setLoading(false)
                    showSuccessState()
                } catch (e: Exception) {
                    setLoading(false)
                    Toast.makeText(
                        this@ResetPasswordActivity,
                        e.message ?: getString(R.string.error_reset),
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        binding.btnBackToLogin.setOnClickListener { finish() }
    }

    private fun showSuccessState() {
        binding.resetForm.visibility = View.GONE
        fadeIn(binding.successView)
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnSendReset.isEnabled = !loading
        binding.btnBackToLogin.isEnabled = !loading
    }
}
