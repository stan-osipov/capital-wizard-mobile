package com.capitalwizard.android.ui.auth

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.view.Menu
import android.view.View
import android.widget.PopupMenu
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.capitalwizard.android.R
import com.capitalwizard.android.utils.LocalePrefs
import com.google.android.material.button.MaterialButton

/**
 * Shared behaviour for the auth screens (sign in / sign up / reset):
 * edge-to-edge status-bar insets, the EN/UA language toggle, and the
 * clickable amber Terms/Privacy legal footer.
 *
 * Auth backend wiring and the WebView token bridge are untouched.
 */
abstract class AuthActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
    }

    /** Pads [target] for the status bar / nav bar so content respects insets. */
    protected fun applyInsets(target: View) {
        ViewCompat.setOnApplyWindowInsetsListener(target) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
    }

    /**
     * Wires the locale pill: shows the current flag + 2-letter code and, on
     * tap, opens a [PopupMenu] listing both languages with the active one
     * checked. Picking one applies it via [LocalePrefs.set], which recreates
     * the activity so the screen re-inflates in the new language.
     */
    protected fun setupLocalePill(button: MaterialButton?) {
        button ?: return
        updateLocalePill(button)
        button.setOnClickListener { anchor -> showLocaleMenu(anchor) }
    }

    /** Sets the pill label to "<flag> <CODE>" for the current language. */
    private fun updateLocalePill(button: MaterialButton) {
        val isUk = LocalePrefs.current() == LocalePrefs.UK
        val code = getString(if (isUk) R.string.locale_code_uk else R.string.locale_code_en)
        button.text = "${LocalePrefs.currentFlag()} $code"
    }

    /** Shows the EN/UA picker anchored to [anchor]; selection applies the locale. */
    private fun showLocaleMenu(anchor: View) {
        val current = LocalePrefs.current()
        val popup = PopupMenu(this, anchor)
        // group 0, itemId = index, order = index
        val itemEn = popup.menu.add(Menu.NONE, ID_LOCALE_EN, 0, R.string.locale_menu_en)
        val itemUk = popup.menu.add(Menu.NONE, ID_LOCALE_UK, 1, R.string.locale_menu_uk)
        // Single-choice check mark on the active language.
        popup.menu.setGroupCheckable(Menu.NONE, true, true)
        itemEn.isChecked = current == LocalePrefs.EN
        itemUk.isChecked = current == LocalePrefs.UK
        popup.setOnMenuItemClickListener { item ->
            val tag = if (item.itemId == ID_LOCALE_UK) LocalePrefs.UK else LocalePrefs.EN
            if (tag != current) {
                // setApplicationLocales recreates active activities on its own
                // (framework LocaleManager on API 33+, AppCompat delegates below),
                // so the screen re-inflates with the new locale automatically.
                LocalePrefs.set(tag)
            }
            true
        }
        popup.show()
    }

    /**
     * Renders the legal footer ("By continuing, you agree to our Terms…")
     * with the Terms / Privacy phrases highlighted in amber and tappable.
     */
    protected fun setupLegalFooter(textView: TextView?) {
        linkifyTermsAndPrivacy(textView, getString(R.string.terms_label))
    }

    /**
     * Highlights "Terms of Service" / "Privacy Policy" (and their Ukrainian
     * equivalents) in amber inside [fullText] and makes them open the
     * respective URLs. Used by the legal footer and the sign-up agreement.
     */
    protected fun linkifyTermsAndPrivacy(textView: TextView?, fullText: String) {
        textView ?: return
        val termsWord = "Terms of Service"
        val privacyWord = "Privacy Policy"
        // Ukrainian variants for span matching when the UK locale is active.
        val termsWordUk = "Умовами використання"
        val privacyWordUk = "Політикою конфіденційності"

        val spannable = SpannableString(fullText)
        val accent = ContextCompat.getColor(this, R.color.accent)

        fun link(word: String, ukWord: String, url: String) {
            var matched = word
            var start = fullText.indexOf(word)
            if (start < 0) {
                matched = ukWord
                start = fullText.indexOf(ukWord)
            }
            if (start < 0) return
            val end = start + matched.length
            spannable.setSpan(object : ClickableSpan() {
                override fun onClick(widget: View) = openUrl(url)
            }, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            spannable.setSpan(
                ForegroundColorSpan(accent), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }

        link(termsWord, termsWordUk, getString(R.string.terms_url))
        link(privacyWord, privacyWordUk, getString(R.string.privacy_url))

        textView.text = spannable
        textView.movementMethod = LinkMovementMethod.getInstance()
        textView.highlightColor = ContextCompat.getColor(this, R.color.accent_soft)
    }

    private fun openUrl(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: Exception) {
            // No browser available — ignore silently.
        }
    }

    /** Fade a view in (used to reveal forms after layout). */
    protected fun fadeIn(view: View, duration: Long = 300L) {
        view.visibility = View.VISIBLE
        view.alpha = 0f
        view.animate().alpha(1f).setDuration(duration).start()
    }

    private companion object {
        const val ID_LOCALE_EN = 1
        const val ID_LOCALE_UK = 2
    }
}
