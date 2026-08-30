package com.capitalwizard.android.ui.auth

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.lifecycleScope
import com.capitalwizard.android.R
import com.capitalwizard.android.databinding.ActivitySignUpBinding
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.services.DeepLinkService
import com.capitalwizard.android.services.ReferralIntake
import com.capitalwizard.android.ui.WebViewActivity
import com.capitalwizard.android.utils.EventCallback
import com.capitalwizard.android.utils.ServiceManager
import kotlinx.coroutines.launch

class SignUpActivity : AuthActivity() {

    private lateinit var binding: ActivitySignUpBinding
    private var authService: AuthService? = null

    private val onLoginCallback = EventCallback<Unit> { navigateToMain() }

    /**
     * Set the moment the person types or pastes into the referral box. From then
     * on a code the device turns up later is dropped rather than written over
     * theirs.
     */
    private var referralTouched = false

    /**
     * True while WE are writing the box. [doAfterTextChanged] cannot tell our own
     * fill from somebody's typing — iOS gets that distinction for free, because
     * its field reports `.editingChanged` only — so the flag draws the line here.
     */
    private var fillingReferral = false

    /** Marshalled onto the main thread: Play answers the install-referrer
     *  connection on a binder thread, and that is the very call this exists for. */
    private val onReferralCodeCallback = EventCallback<String> { code ->
        runOnUiThread { fillReferral(code) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setEnterTransition(R.anim.cw_fade_in, R.anim.cw_fade_out)

        binding = ActivitySignUpBinding.inflate(layoutInflater)
        setContentView(binding.root)

        applyInsets(binding.root)
        setupLocalePill(binding.appBar.btnLanguage)
        setupLegalFooter(binding.legalFooter)
        linkifyTermsAndPrivacy(binding.termsAgreeText, getString(R.string.signup_terms_agree))

        authService = ServiceManager.getService<AuthService>()
        authService?.onLogin?.subscribe(onLoginCallback)

        applyReferralPrefill()

        // Primary button is gated by the terms checkbox.
        binding.btnCreateAccount.isEnabled = binding.checkboxTerms.isChecked
        binding.checkboxTerms.setOnCheckedChangeListener { _, checked ->
            binding.btnCreateAccount.isEnabled = checked
        }

        setupListeners()
    }

    /**
     * Puts a code in the box if this device has one to offer.
     *
     * Runs when the screen is built rather than at launch, because the clipboard
     * leg of [ReferralIntake] is user-visible — Android 12+ toasts when an app
     * reads the clipboard — and this is the one screen where the answer is used.
     */
    private fun applyReferralPrefill() {
        // The paste button is for an EMPTY box. Once there is a code in there,
        // offering to replace it is offering to undo what just happened.
        binding.inputReferral.doAfterTextChanged {
            if (!fillingReferral) referralTouched = true
            binding.layoutReferral.error = null
            updateReferralPasteVisibility()
        }
        // The suffix TextView IS the button — see the layout for why Paste is a
        // suffix and not an end icon. Material draws it as plain text, so the
        // touch target has to be widened by hand; without the padding it is the
        // width of the glyphs, which on «Вставити» is legible and on "Paste"
        // is not.
        binding.layoutReferral.suffixTextView.apply {
            isClickable = true
            isFocusable = true
            setPadding(dp(12), dp(14), dp(6), dp(14))
            setOnClickListener { pasteReferralFromClipboard() }
        }

        val deepLink = ServiceManager.getService<DeepLinkService>()
        ReferralIntake.prefill(this, deepLink)?.let { fillReferral(it) }
        updateReferralPasteVisibility()

        // A code can arrive AFTER this screen is up, and on Android that is the
        // NORMAL case rather than the edge one: the Play install referrer — the
        // only thing that crosses a store install here — is fetched over a
        // background connection that answers a moment after launch, by which time
        // this screen is already on the table. A prefill read once in `onCreate`
        // would miss the code every time it mattered most.
        deepLink?.onReferralCode?.subscribe(onReferralCodeCallback)
    }

    /**
     * Writes a code the device found into the box — unless the person has started
     * filling it in themselves, in which case theirs wins. Silent by design: the
     * hint under the field already says the box fills itself.
     */
    private fun fillReferral(code: String) {
        if (referralTouched) return
        fillingReferral = true
        binding.layoutReferral.error = null
        binding.inputReferral.setText(code)
        fillingReferral = false
        updateReferralPasteVisibility()
    }

    /**
     * The paste button is for an EMPTY box. Once there is a code in there,
     * offering to replace it is offering to undo what just happened.
     *
     * Driven by SETTING the suffix text rather than by touching the TextView's
     * visibility: Material recomputes that visibility whenever the label state
     * changes, so a hand-set `GONE` comes back on the next focus change.
     */
    private fun setReferralPasteVisible(visible: Boolean) {
        binding.layoutReferral.suffixText =
            if (visible) getString(R.string.signup_referral_paste) else null
    }

    private fun updateReferralPasteVisibility() {
        setReferralPasteVisible(binding.inputReferral.text.toString().trim().isEmpty())
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    /**
     * Fills the box from the clipboard. Read here, in the button's own handler,
     * so the system's clipboard-access toast lands on an action the person just
     * took — never unprompted at launch.
     *
     * A paste that is not a code is REFUSED rather than dropped into the field:
     * somebody who pasted the wrong thing needs to see that, and a box silently
     * left empty after a deliberate tap reads as a broken button.
     */
    private fun pasteReferralFromClipboard() {
        val code = ReferralIntake.fromPaste(ReferralIntake.clipboardText(this))
        if (code == null) {
            binding.layoutReferral.error = getString(R.string.error_referral_invalid)
            return
        }
        binding.layoutReferral.error = null
        // Pasting is as deliberate as typing, so it locks the box the same way:
        // a code arriving from Play a second later must not replace it.
        referralTouched = true
        binding.inputReferral.setText(code)
    }

    /**
     * Hands whatever is in the box to the web app, whichever way the account ends
     * up being created — the field is editable, so what they SEND is what has to
     * travel, not what arrived.
     */
    private fun stashReferralCode() {
        val raw = binding.inputReferral.text.toString().trim()
        if (raw.isEmpty()) return
        ServiceManager.getService<DeepLinkService>()?.stashReferral(raw)
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
            // Optional, so an empty box always passes. But a code somebody typed
            // and got wrong must not be swallowed silently — that reads as
            // "applied" and is only discovered when the bonus never arrives.
            val referral = binding.inputReferral.text.toString().trim()
            if (referral.isNotEmpty() && ReferralIntake.normalized(referral) == null) {
                binding.layoutReferral.error = getString(R.string.error_referral_invalid)
                return@setOnClickListener
            }
            binding.layoutReferral.error = null

            stashReferralCode()
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
            // Social sign-up creates the account just as the form does, so the
            // code has to be handed over here too.
            stashReferralCode()
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
        setReferralPasteVisible(
            !loading && binding.inputReferral.text.toString().trim().isEmpty()
        )
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
        ServiceManager.getService<DeepLinkService>()?.onReferralCode?.unsubscribe(onReferralCodeCallback)
    }
}
