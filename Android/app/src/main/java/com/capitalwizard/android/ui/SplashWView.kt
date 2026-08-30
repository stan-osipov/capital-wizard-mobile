package com.capitalwizard.android.ui

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.provider.Settings
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import androidx.core.content.ContextCompat
import com.capitalwizard.android.R
import com.capitalwizard.android.utils.AccentColors

/**
 * In-app "Line Draw" splash mark — the Capital Wizard W plotted as a rising chart
 * line, drawn in the user's chosen accent (mirrors the web `.preloader--fullscreen`
 * and the iOS `SplashAnimationView`). Shown over the WebView while the page loads,
 * bridging from the brief OS system splash.
 *
 * The OS system splash W (`windowSplashScreenAnimatedIcon`) is coloured from a
 * static resource and can't read a per-user accent, so this in-app mark is what
 * makes the Android splash react to the accent — resolved from the id the WebView
 * last reported (`cw_web_accent`).
 *
 * Geometry + timing mirror the iOS splash: a 118dp W in a faint full-W track, an
 * accent stroke that draws itself (0→55%), holds (to 80%), fades (to 100%), loops.
 */
class SplashWView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : View(context, attrs, defStyle) {

    private companion object {
        // W on a 0–100 space (traced from the app icon): an asymmetric, rising
        // chart zig-zag (NOT a symmetric W) — matches ic_splash_w / iOS markPoints.
        val MARK_POINTS = arrayOf(
            13f to 45f, 31f to 83f, 45f to 34f, 63.5f to 66f, 87f to 18f,
        )
        const val MARK_DP = 118f        // mark size (matches iOS markSize)
        const val STROKE_UNITS = 6f     // stroke width in the 0–100 space
        const val DRAW_MS = 2400L       // full draw→hold→fade loop
        const val DRAW_END = 0.55f      // stroke fully drawn by 55%
        const val FADE_START = 0.80f    // hold until 80%, then fade to 100%
    }

    private val density = resources.displayMetrics.density
    private val markPx = MARK_DP * density
    private val strokePx = STROKE_UNITS * (markPx / 100f)

    // The handoff design's cubic-bezier(0.65, 0, 0.35, 1), applied to the draw phase.
    private val easing = PathInterpolator(0.65f, 0f, 0.35f, 1f)

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = strokePx
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = strokePx
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val markPath = Path()
    private val segment = Path()
    private val measure = PathMeasure()
    private var pathLen = 0f

    private var trim = 0f
    private var lineAlpha = 255

    private var animator: ValueAnimator? = null

    init {
        // setShadowLayer (the accent glow) needs a software layer.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        applyColors()
    }

    private fun isDark(): Boolean =
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private fun applyColors() {
        val dark = isDark()
        val accent = AccentColors.accent(context, dark)
        trackPaint.color = ContextCompat.getColor(context, R.color.border)
        linePaint.color = accent
        // Accent glow ≈ CSS drop-shadow(0 0 6px var(--accent-soft)): accent hue at
        // low alpha (matches the iOS dsAccentSoft glow model — 0.20 dark / 0.16 light).
        val softAlpha = if (dark) 51 else 41 // 0.20 / 0.16 of 255
        val soft = (accent and 0x00FFFFFF) or (softAlpha shl 24)
        linePaint.setShadowLayer(strokePx, 0f, 0f, soft)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        buildPath(w, h)
    }

    private fun buildPath(w: Int, h: Int) {
        val scale = markPx / 100f
        val left = (w - markPx) / 2f
        val top = (h - markPx) / 2f
        markPath.reset()
        MARK_POINTS.forEachIndexed { i, (x, y) ->
            val px = left + x * scale
            val py = top + y * scale
            if (i == 0) markPath.moveTo(px, py) else markPath.lineTo(px, py)
        }
        measure.setPath(markPath, false)
        pathLen = measure.length
    }

    override fun onDraw(canvas: Canvas) {
        if (pathLen <= 0f) return
        canvas.drawPath(markPath, trackPaint)
        if (trim > 0f) {
            segment.reset()
            measure.getSegment(0f, pathLen * trim, segment, true)
            linePaint.alpha = lineAlpha
            canvas.drawPath(segment, linePaint)
        }
    }

    /**
     * Whether the device has animations switched off (Developer options, or the
     * accessibility "remove animations" setting). The iOS splash reads
     * `UIAccessibility.isReduceMotionEnabled` here; Android expresses the same
     * preference as an animator duration scale of 0.
     */
    private fun animationsDisabled(): Boolean =
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f

    private fun startAnim() {
        if (animator != null) return

        // Reduced motion: show the finished accent W and no draw loop, which is
        // exactly what the iOS splash does. Drawing nothing would leave only the
        // faint track, and the mark is the one thing on this screen.
        if (animationsDisabled()) {
            trim = 1f
            lineAlpha = 255
            invalidate()
            return
        }

        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = DRAW_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator() // linear driver; phases eased manually
            addUpdateListener {
                val p = it.animatedFraction
                trim = if (p >= DRAW_END) 1f else easing.getInterpolation(p / DRAW_END)
                lineAlpha = if (p <= FADE_START) {
                    255
                } else {
                    (255f * (1f - (p - FADE_START) / (1f - FADE_START))).toInt().coerceIn(0, 255)
                }
                invalidate()
            }
            start()
        }
    }

    private fun stopAnim() {
        animator?.cancel()
        animator = null
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        if (isVisible) {
            applyColors()
            startAnim()
        } else {
            stopAnim()
        }
    }

    override fun onDetachedFromWindow() {
        stopAnim()
        super.onDetachedFromWindow()
    }
}
