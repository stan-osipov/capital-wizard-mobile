package com.capitalwizard.android.services

import android.content.ClipboardManager
import android.content.Context
import com.capitalwizard.android.utils.CWLog

/**
 * Where a referral code comes from on this device, and what shape it has to be.
 * Mirrors the iOS `ReferralIntake`.
 *
 * A code has to survive the gap between "I tapped Olena's link" and "I filled in
 * the sign-up form", and on a phone that gap can contain the Play Store. Sources,
 * tried in this order:
 *
 *  1. **An app link this launch** — `capital-wizard.com/r/CODE` reached
 *     [DeepLinkService] because the app was already installed.
 *  2. **The Play install referrer** — recovered by [InstallReferrerService],
 *     which stashes the code when the install itself carried it. This is the leg
 *     iOS does not have: Apple ships no install-time payload of any kind, which
 *     is why the clipboard below matters far more over there.
 *  3. **The clipboard, on a tap** — the claim page prints the code beside a
 *     Copy button. Kept here as well as on iOS so the two shells behave the
 *     same, and because it also covers a sideload, where Play has no referrer to
 *     give. Read from an explicit paste button, never automatically: iOS punishes
 *     an unprompted read with a modal alert that defaults to refusing, and
 *     Android 12+ toasts every read — neither belongs on a first launch, before
 *     the person has seen a screen of the app.
 *  4. **Typed by hand** — the field is always present and always editable, and
 *     the server still accepts a code for a week after the account is created.
 *
 * None of this is a guarantee and it must not pretend to be. A wrong code sitting
 * in the box is worse than an empty box, so every source is validated against the
 * same alphabet the database's own check constraint uses before it is shown.
 */
object ReferralIntake {

    /**
     * A paste holding a whole article is somebody's reading, not a code.
     * Applied before the value is used, so a large paste is discarded outright.
     */
    const val MAX_PASTE_LENGTH = 64

    private const val PREFS = "cw_referral_intake"
    private const val KEY_CODE = "pending_code"
    private const val KEY_SAVED_AT = "pending_saved_at"

    /**
     * Generous by design, and the same window `src/lib/pendingReferral.ts` uses
     * on the web: somebody may meet the link days before they sign up, and a
     * stale code costs nothing — the server still refuses one once the account is
     * over a week old. 30 days, matching the attribution window we advertise.
     */
    private const val MAX_AGE_MS = 30L * 24 * 60 * 60 * 1000

    /**
     * Upper-cases and trims [raw], returning it only if it could be a referral
     * code. The alphabet matches [DeepLinkService.referralCode] and the
     * database's own check constraint: anything else is not a code we could
     * resolve, so showing it would only invite somebody to submit it.
     */
    fun normalized(raw: String?): String? {
        val code = raw?.trim()?.uppercase() ?: return null
        if (code.length !in 3..32) return null
        if (!code.all { (it.isLetterOrDigit() && it.code < 128) || it == '-' }) return null
        if (code.first() == '-') return null
        return code
    }

    /**
     * Keeps a code across app launches.
     *
     * [DeepLinkService] holds it in memory, which lasts exactly as long as the
     * process: somebody who taps the link, reaches the form and then puts their
     * phone down has lost it by the time they come back. That is the same gap the
     * Play Store opens, one launch later, so it gets the same answer.
     */
    fun remember(context: Context, raw: String) {
        val code = normalized(raw) ?: return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_CODE, code)
            .putLong(KEY_SAVED_AT, System.currentTimeMillis())
            .apply()
    }

    /** The remembered code, if there is one and it has not gone stale. */
    fun remembered(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val code = normalized(prefs.getString(KEY_CODE, null)) ?: return null
        val savedAt = prefs.getLong(KEY_SAVED_AT, 0L)
        if (savedAt <= 0L || System.currentTimeMillis() - savedAt > MAX_AGE_MS) {
            forget(context)
            return null
        }
        return code
    }

    /**
     * Drops the remembered code.
     *
     * Called once an account has signed in on this device: from that moment the
     * web app owns redemption, and leaving it here would pre-fill somebody else's
     * code onto a SECOND account created on the same phone.
     */
    fun forget(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(KEY_CODE).remove(KEY_SAVED_AT).apply()
    }

    /**
     * The code to put in the sign-up field, or `null` to leave it empty.
     *
     * Only the link and Play-referrer legs are automatic — this launch's, or one
     * remembered from an earlier one. Everything else is a deliberate act by the
     * person: the paste button, or the keyboard.
     */
    fun prefill(context: Context, deepLinkService: DeepLinkService?): String? {
        normalized(deepLinkService?.pendingReferralCode)?.let {
            CWLog.log("Referral prefill from deep link → $it", category = "Referral")
            return it
        }
        remembered(context)?.let {
            CWLog.log("Referral prefill from an earlier launch → $it", category = "Referral")
            return it
        }
        return null
    }

    /** A pasted string turned into a code, or `null` if it is not one. */
    fun fromPaste(raw: String?): String? {
        if (raw == null || raw.length > MAX_PASTE_LENGTH) return null
        return normalized(raw)
    }

    /**
     * The clipboard's current text, or `null`. Called ONLY from the paste
     * button's own click handler, so the system's clipboard-access toast lands
     * on an action the person just took.
     */
    fun clipboardText(context: Context): String? = runCatching {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboard?.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(context)
            ?.toString()
    }.getOrNull()
}
