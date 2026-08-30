package com.capitalwizard.android.utils

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo

/**
 * Phone or tablet — decided once, and read by everything that cares.
 *
 * Two things depend on this answer and must never disagree: the chrome the web
 * app picks (`__capital_wizard_native.idiom`, see [WebViewBridge]) and whether
 * the screen may rotate. A tablet running the DESKTOP chrome while pinned to
 * portrait is the failure this file exists to prevent.
 *
 * iOS asks `UIDevice.current.userInterfaceIdiom == .pad`; Android has no such
 * flag, so the equivalent is the smallest-width bucket the platform itself uses
 * to separate the two form factors.
 */
object DeviceIdiom {

    /** Value the web app reads for tablet chrome. Mirrors iOS's `.pad`. */
    const val PAD = "pad"

    /** Value the web app reads for phone chrome. Mirrors iOS's `.phone`. */
    const val PHONE = "phone"

    /** The platform's own phone/tablet boundary — the `sw600dp` resource bucket. */
    private const val TABLET_MIN_WIDTH_DP = 600

    fun isTablet(context: Context): Boolean =
        context.resources.configuration.smallestScreenWidthDp >= TABLET_MIN_WIDTH_DP

    fun of(context: Context): String = if (isTablet(context)) PAD else PHONE
}

/**
 * Pins a phone to portrait and leaves a tablet free to rotate, mirroring the
 * iOS shell exactly — `AppDelegate.supportedInterfaceOrientationsFor` returns
 * `.portrait` for an iPhone and `.all` for an iPad, and every view controller
 * repeats it. Change one shell's rule and the other has to move with it.
 *
 * Deliberately NOT `android:screenOrientation="portrait"` in the manifest: that
 * attribute takes a literal, so it cannot ask which device it is running on and
 * would pin tablets too — and a tablet is exactly where the web app switches to
 * the desktop chrome, side-by-side layouts and all.
 *
 * `FULL_USER` rather than `FULL_SENSOR` for the tablet: all four orientations,
 * but still obeying the system rotation lock, because a user who has locked
 * their tablet meant it. It matches iOS's `.all`, which includes upside-down.
 * The phone gets `PORTRAIT`, not `USER_PORTRAIT` — one orientation, same as the
 * iPhone's `.portrait` mask, which likewise excludes upside-down.
 *
 * Call from `onCreate` before `setContentView`, so the first frame is already
 * the right way up.
 *
 * Note for API 36: on large screens the system now ignores an app's orientation
 * request outright. That lands on the side we already want — phones (< 600dp)
 * keep the lock, tablets rotate — so this stays correct rather than merely
 * tolerated.
 */
fun Activity.applyIdiomOrientation() {
    requestedOrientation = if (DeviceIdiom.isTablet(this)) {
        ActivityInfo.SCREEN_ORIENTATION_FULL_USER
    } else {
        ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }
}
