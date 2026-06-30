package com.capitalwizard.android.utils

import android.content.Context

/**
 * Generic device-local key→value store, mirrored from the WebView's `deviceStore`
 * (src/lib/deviceStore.ts). The web owns the namespace and sends the *exact*
 * localStorage key over the bridge; we persist each pair verbatim and replay
 * `localStorage.setItem(key, value)` on the next launch (pre-paint), so a value
 * the web stores survives a WebView data wipe (e.g. logout) and an app relaunch —
 * all without any native change per new key.
 *
 * Stored in its own [android.content.SharedPreferences] file so the whole set can
 * be enumerated for seeding. Device-local — never the database.
 */
object DeviceKvStore {

    private const val PREFS_NAME = "cw_kv_store"

    /**
     * Only keys under this namespace are accepted — a safety guard so the bridge
     * can never be coaxed into persisting/seeding unrelated localStorage keys
     * (e.g. the Supabase auth token). Must match `PREFIX` in deviceStore.ts.
     */
    const val WEB_KEY_PREFIX = "cw-kv:"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Every saved pair (full localStorage key → value). */
    fun all(context: Context): Map<String, String> {
        @Suppress("UNCHECKED_CAST")
        return prefs(context).all.filterValues { it is String } as Map<String, String>
    }

    fun set(context: Context, key: String, value: String) {
        if (!key.startsWith(WEB_KEY_PREFIX)) return
        prefs(context).edit().putString(key, value).apply()
    }

    fun remove(context: Context, key: String) {
        if (!key.startsWith(WEB_KEY_PREFIX)) return
        prefs(context).edit().remove(key).apply()
    }
}
