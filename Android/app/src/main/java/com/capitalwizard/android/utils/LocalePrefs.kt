package com.capitalwizard.android.utils

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.ConfigurationCompat
import androidx.core.os.LocaleListCompat

/**
 * EN/UA in-app language toggle using the AppCompat per-app locales API
 * (androidx.appcompat 1.6+; this project uses 1.7.0).
 *
 * AppCompatDelegate.setApplicationLocales persists the choice automatically
 * via the platform locale-storage service (API 33+) or AppCompat's own
 * backing store (API < 33), so no manual SharedPreferences write is needed.
 */
object LocalePrefs {

    const val EN = "en"
    const val UK = "uk"

    /**
     * The language the app is ACTUALLY showing.
     *
     * Two sources, in order, and reading only the first was a bug: an explicit
     * per-app override if the user has ever picked one, otherwise the locale the
     * resources themselves resolved against — which is what chose `values-uk` on
     * a Ukrainian phone. [AppCompatDelegate.getApplicationLocales] is EMPTY until
     * somebody picks a language, so defaulting to [EN] there made the pill read
     * "🇬🇧 EN" over a fully Ukrainian screen, and the picker show English as the
     * active choice. That was not only wrong to look at: tapping English was then
     * a no-op against `current`, so a fresh install on a Ukrainian phone had no
     * way to reach English at all except by going to Ukrainian and back.
     *
     * The iOS shell has always answered this question properly —
     * `LocalizationManager.currentLanguage` falls back to
     * `Locale.preferredLanguages` and then the device region — so this is the
     * Android side catching up rather than a new rule.
     *
     * No separate region check is needed to mirror iOS's `region == "UA"` arm:
     * the resource configuration is the answer AFTER the platform has resolved
     * language, region and every other qualifier, so it already reflects
     * whatever made Android pick the Ukrainian resources.
     */
    fun current(context: Context): String {
        val explicit = AppCompatDelegate.getApplicationLocales()
        val tag = if (!explicit.isEmpty) {
            explicit[0]?.language
        } else {
            ConfigurationCompat.getLocales(context.resources.configuration)[0]?.language
        }
        return if (tag == UK) UK else EN
    }

    /** The flag emoji shown on the toggle for the CURRENT language. */
    fun currentFlag(context: Context): String = if (current(context) == UK) "🇺🇦" else "🇬🇧"

    /** Apply (and persist) a specific language tag. */
    fun set(tag: String) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))
    }

    /** Switch to the other language and return the new tag. */
    fun toggle(context: Context): String {
        val next = if (current(context) == UK) EN else UK
        set(next)
        return next
    }
}
