package com.capitalwizard.android.ui

import android.os.Handler
import android.os.Looper

/**
 * The line of text under the launch splash's wordmark — "Creating browser…",
 * "Loading app…" — and the animated dots after it.
 *
 * This is the Android spelling of iOS's `SplashAnimationView.postStatus`, which
 * broadcasts through NotificationCenter. The point is the same on both shells:
 * the boot steps happen in files that know nothing about the splash view, and
 * the longest silence in the whole launch (the WebView coming up) is exactly
 * the stretch where a reader most needs to be told something is happening.
 *
 * [post] may be called from any thread and before anything is bound; the last
 * value is retained so a listener attaching late still shows the current step
 * rather than the default caption.
 */
object SplashStatus {

    private val main = Handler(Looper.getMainLooper())

    /** The most recent step, or null while the splash is still on its default. */
    @Volatile
    var current: String? = null
        private set

    private var listener: ((String) -> Unit)? = null

    /** Reports a boot step. Safe from any thread; a no-op if nothing is bound. */
    fun post(text: String) {
        if (text.isBlank()) return
        current = text
        main.post { listener?.invoke(text) }
    }

    /**
     * Attaches the splash's caption. Replays [current] immediately so a step
     * reported before the view existed is not lost. Pass null on teardown —
     * the Activity holds the view, and a retained lambda would hold the
     * Activity with it.
     */
    fun bind(listener: ((String) -> Unit)?) {
        this.listener = listener
        val text = current
        if (listener != null && text != null) main.post { listener(text) }
    }

    /**
     * Forgets the last step so the NEXT launch starts on the localized default
     * caption rather than on "Waiting for app ready…" from the run before.
     * Called when the splash is revealed away.
     */
    fun reset() {
        current = null
    }
}
