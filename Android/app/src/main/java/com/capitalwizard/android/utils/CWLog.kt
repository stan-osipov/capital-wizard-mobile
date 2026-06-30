package com.capitalwizard.android.utils

import android.os.Process
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * In-memory ring buffer of structured app log lines, surfaced to the web app's bug
 * reporter via the native bridge (`request-logs`). Mirrors the iOS `CWLog`.
 *
 * Call [log] at notable points (lifecycle, errors) so the bug report has reliable,
 * detailed native output regardless of what — if anything — the system writes to
 * logcat. Each line is also mirrored to logcat (via [Log]) for live `adb` debugging.
 *
 * [readRecentLogcat] remains available as a best-effort *extra* source of raw
 * process logcat (system/WebView/SDK output), but the ring buffer is the reliable
 * primary source: on many OEM ROMs an app can no longer read even its own logcat,
 * which is exactly why relying on it alone returned no lines.
 */
object CWLog {
    private const val MAX_LINES = 500
    private const val LOGCAT_MAX_LINES = 300
    private const val TAG = "CapitalWizard"

    private val lines = ArrayDeque<String>()
    private val lock = Any()
    private val timeFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    /** Append a timestamped line to the ring buffer and mirror it to logcat. */
    fun log(message: String, category: String = "App") {
        synchronized(lock) {
            lines.addLast("${timeFormat.format(Date())} [$category] $message")
            while (lines.size > MAX_LINES) lines.removeFirst()
        }
        Log.i(TAG, "[$category] $message")
    }

    /** Snapshot of the buffered structured lines (oldest → newest). */
    fun snapshot(): List<String> = synchronized(lock) { lines.toList() }

    /**
     * Best-effort raw logcat for this process — extra detail beyond [snapshot].
     *
     * Since Android 4.1 an app can only read log entries from its own process, so a
     * `logcat -d` dump scoped to our PID returns this app's `Log.*`, `println`, and
     * stack-trace output (`System.out` / `System.err` are routed to logcat). `-d`
     * dumps and exits, so the read never blocks. May legitimately return nothing on
     * ROMs that block self-log reads — the ring buffer covers that case.
     */
    fun readRecentLogcat(): List<String> {
        return try {
            val pid = Process.myPid().toString()
            val process = Runtime.getRuntime().exec(
                arrayOf("logcat", "-d", "-v", "time", "--pid", pid)
            )
            val out = process.inputStream.bufferedReader().useLines { it.toList() }
            process.destroy()
            if (out.size > LOGCAT_MAX_LINES) out.takeLast(LOGCAT_MAX_LINES) else out
        } catch (e: Exception) {
            listOf("Failed to read logcat: ${e.message}")
        }
    }
}
