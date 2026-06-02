package com.capitalwizard.android.utils

import androidx.appcompat.app.AppCompatDelegate
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

    /** Currently applied language tag, defaulting to English when unset. */
    fun current(): String {
        val locales = AppCompatDelegate.getApplicationLocales()
        val tag = if (!locales.isEmpty) locales[0]?.language else null
        return if (tag == UK) UK else EN
    }

    /** The flag emoji shown on the toggle for the CURRENT language. */
    fun currentFlag(): String = if (current() == UK) "🇺🇦" else "🇬🇧"

    /** Apply (and persist) a specific language tag. */
    fun set(tag: String) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))
    }

    /** Switch to the other language and return the new tag. */
    fun toggle(): String {
        val next = if (current() == UK) EN else UK
        set(next)
        return next
    }
}
