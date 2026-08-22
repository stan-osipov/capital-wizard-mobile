package com.capitalwizard.android.utils

import android.content.Context
import android.graphics.Color
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Resolves the user's chosen in-app accent to a native colour, mirroring the web
 * design system (ThemeService `ACCENT_SWATCHES` + `ACCENT_PROFILE`) and the iOS
 * `AppColors.webAccent`. Used so brand surfaces that should track the accent (the
 * in-app launch splash W) match the web instead of the fixed amber brand.
 *
 * The accent id is the exact value the WebView last reported (`cw_web_accent`,
 * via [ThemePrefs.getWebAccent]); it defaults to amber until the web reports one.
 */
object AccentColors {

    /** hue (degrees) + optional chroma override per accent id — mirror of ACCENT_SWATCHES. */
    private val swatches: Map<String, Pair<Double, Double?>> = mapOf(
        "amber" to (55.0 to null),
        "indigo" to (275.0 to null),
        "blue" to (240.0 to null),
        "teal" to (180.0 to null),
        "green" to (145.0 to null),
        "red" to (25.0 to null),
        "pink" to (350.0 to null),
        "mono" to (240.0 to 0.0),
    )

    /**
     * The accent colour for the current accent id + scheme. Mirrors the web
     * `ACCENT_PROFILE` accent channel; dark-soft collapses to dark natively.
     */
    fun accent(context: Context, isDark: Boolean): Int {
        val id = ThemePrefs.getWebAccent(context)?.takeIf { swatches.containsKey(it) } ?: "amber"
        val (hue, chromaOverride) = swatches.getValue(id)
        val l = if (isDark) 0.68 else 0.62
        val c = chromaOverride ?: if (isDark) 0.16 else 0.17
        return oklchToColor(l, c, hue)
    }

    /** OKLCH (L 0–1, chroma C, hue H degrees) → sRGB colour int (OKLab → linear sRGB → gamma). */
    fun oklchToColor(l: Double, c: Double, hueDegrees: Double): Int {
        val hr = hueDegrees * Math.PI / 180.0
        val a = c * cos(hr)
        val b = c * sin(hr)

        val lPrime = l + 0.3963377774 * a + 0.2158037573 * b
        val mPrime = l - 0.1055613458 * a - 0.0638541728 * b
        val sPrime = l - 0.0894841775 * a - 1.2914855480 * b
        val l3 = lPrime * lPrime * lPrime
        val m3 = mPrime * mPrime * mPrime
        val s3 = sPrime * sPrime * sPrime

        val rLin = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        val gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        val bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

        return Color.rgb(enc(rLin), enc(gLin), enc(bLin))
    }

    /** linear sRGB channel → gamma-encoded 0–255. */
    private fun enc(x: Double): Int {
        val v = x.coerceIn(0.0, 1.0)
        val s = if (v <= 0.0031308) 12.92 * v else 1.055 * v.pow(1.0 / 2.4) - 0.055
        return (s * 255.0).roundToInt().coerceIn(0, 255)
    }
}
