package com.capitalwizard.android.utils

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

/**
 * Persists the user's theme override and applies it via AppCompatDelegate.
 *
 * Values: "system" (default) | "light" | "dark".
 * - system → MODE_NIGHT_FOLLOW_SYSTEM
 * - light  → MODE_NIGHT_NO
 * - dark   → MODE_NIGHT_YES
 */
object ThemePrefs {

    private const val PREFS_NAME = "cw_prefs"
    const val KEY_THEME = "cw_theme_pref"

    const val SYSTEM = "system"
    const val LIGHT = "light"
    const val DARK = "dark"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Current stored preference (defaults to system). */
    fun get(context: Context): String =
        prefs(context).getString(KEY_THEME, SYSTEM) ?: SYSTEM

    /** Apply the stored preference to the AppCompat night-mode delegate. */
    fun apply(context: Context) {
        applyMode(get(context))
    }

    /** Persist a new preference and apply it immediately. */
    fun set(context: Context, mode: String) {
        prefs(context).edit().putString(KEY_THEME, mode).apply()
        applyMode(mode)
    }

    private fun applyMode(mode: String) {
        val nightMode = when (mode) {
            LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            DARK -> AppCompatDelegate.MODE_NIGHT_YES
            else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
        }
        AppCompatDelegate.setDefaultNightMode(nightMode)
    }
}
