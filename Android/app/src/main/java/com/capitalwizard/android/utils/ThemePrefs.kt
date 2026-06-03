package com.capitalwizard.android.utils

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

/**
 * Persists the user's theme override and applies it via AppCompatDelegate.
 *
 * Two parallel concepts are stored here:
 *
 * 1. The native night-mode override ([KEY_THEME]): "system" (default) | "light" | "dark".
 *    - system → MODE_NIGHT_FOLLOW_SYSTEM
 *    - light  → MODE_NIGHT_NO
 *    - dark   → MODE_NIGHT_YES
 *
 * 2. The *exact* web theme/accent strings ([KEY_WEB_THEME] / [KEY_WEB_ACCENT]), mirrored
 *    from the WebView so the native shell can re-seed the page on the next launch (pre-paint).
 *    These are stored losslessly — e.g. the web "dark-soft" mode is preserved verbatim even
 *    though it collapses to MODE_NIGHT_YES on the native side. This is a *device-local*
 *    preference (never the database).
 */
object ThemePrefs {

    private const val PREFS_NAME = "cw_prefs"
    const val KEY_THEME = "cw_theme_pref"

    // Verbatim web values mirrored from the WebView bridge (lossless).
    const val KEY_WEB_THEME = "cw_web_theme"
    const val KEY_WEB_ACCENT = "cw_web_accent"

    const val SYSTEM = "system"
    const val LIGHT = "light"
    const val DARK = "dark"

    // Web `mode` values (from ThemeService): light | dark | dark-soft | auto.
    const val WEB_AUTO = "auto"
    const val WEB_LIGHT = "light"
    const val WEB_DARK = "dark"
    const val WEB_DARK_SOFT = "dark-soft"

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

    /** The exact web `mode` string last seen from the WebView, or null if none. */
    fun getWebTheme(context: Context): String? =
        prefs(context).getString(KEY_WEB_THEME, null)

    /** The exact web `accent` id last seen from the WebView, or null if none. */
    fun getWebAccent(context: Context): String? =
        prefs(context).getString(KEY_WEB_ACCENT, null)

    /**
     * Persist the verbatim web theme/accent strings AND apply the corresponding native
     * night mode. Either value may be null/blank (only the provided one is written).
     *
     * Mode → night-mode mapping (matches the web's resolution, with both dark variants
     * collapsing to the AppCompat dark mode):
     *   auto      → MODE_NIGHT_FOLLOW_SYSTEM
     *   light     → MODE_NIGHT_NO
     *   dark      → MODE_NIGHT_YES
     *   dark-soft → MODE_NIGHT_YES
     *
     * NOTE: [AppCompatDelegate.setDefaultNightMode] must be called on the main thread.
     * Callers receiving this from a binder/JS-bridge thread should hop to the UI thread.
     */
    fun setFromWeb(context: Context, webMode: String?, webAccent: String?) {
        prefs(context).edit().apply {
            if (!webMode.isNullOrBlank()) putString(KEY_WEB_THEME, webMode)
            if (!webAccent.isNullOrBlank()) putString(KEY_WEB_ACCENT, webAccent)
            apply()
        }
        if (!webMode.isNullOrBlank()) {
            // Mirror the web mode onto the native night-mode override so the shell
            // (splash / auth screens) matches the WebView.
            val nativeMode = when (webMode) {
                WEB_LIGHT -> LIGHT
                WEB_DARK, WEB_DARK_SOFT -> DARK
                else -> SYSTEM // auto (and any unknown value) follows the system
            }
            set(context, nativeMode)
        }
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
