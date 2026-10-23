package com.capitalwizard.android.ui

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.provider.Settings
import android.util.AttributeSet
import android.view.View
import android.view.animation.PathInterpolator
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.capitalwizard.android.R
import com.capitalwizard.android.utils.AccentColors
import com.capitalwizard.android.utils.ThemePrefs
import kotlin.math.cos

/** Native counterpart of FlaskLoader.tsx / flask-loader.css. The same 48-unit
 * paths, 96dp glyph, 22dp caption gap and wall-clock phases also run on iOS.
 * The web owns the fill/flood exit once its first painted frame takes over. */
class CodingLabSplashView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bubbleEase = PathInterpolator(.4f, 0f, .6f, 1f)
    private val steamEase = PathInterpolator(0f, 0f, .58f, 1f)
    private val glass = Path().apply {
        moveTo(21f,6f); lineTo(21f,18f); lineTo(9.5f,37.5f)
        quadTo(8f,42f,13f,42f); lineTo(35f,42f)
        quadTo(40f,42f,38.5f,37.5f); lineTo(27f,18f); lineTo(27f,6f)
    }
    private val clip = Path(glass).apply { close() }
    private val wave = Path().apply {
        moveTo(-48f,0f)
        for (x in -48 until 96 step 12) {
            quadTo(x+3f,-2.6f,x+6f,0f); quadTo(x+9f,2.6f,x+12f,0f)
        }
        lineTo(96f,60f); lineTo(-48f,60f); close()
    }
    private val cap = Path().apply { moveTo(18.5f,6f); lineTo(29.5f,6f) }
    private val steam = (0..2).map { i ->
        val x = 21f+i*3f; val y = if (i == 1) 2f else 3f; val dx = if (i == 1) 1.6f else -1.6f
        Path().apply { moveTo(x,y); quadTo(x+dx,y-2,x,y-4); quadTo(x-dx,y-6,x,y-8) }
    }
    private val bubbles = arrayOf(floatArrayOf(20f,38f,1.7f,0f,-2f),floatArrayOf(26f,39f,1.3f,.8f,2f),floatArrayOf(23f,37f,2f,1.6f,-1f))
    private fun phase(seconds: Double, delay: Float = 0f): Float =
        (((System.currentTimeMillis()/1000.0-delay) % seconds)/seconds).toFloat()
    private fun color(l: Double, c: Double, h: Double = 240.0) = AccentColors.oklchToColor(l,c,h)
    init { contentDescription = context.getString(R.string.loader_caption) }

    override fun onDraw(canvas: Canvas) {
        val density = resources.displayMetrics.density
        val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val soft = dark && ThemePrefs.getWebTheme(context) == ThemePrefs.WEB_DARK_SOFT
        val bg = if (soft) color(.24,.008,248.0) else if (dark) color(.16,.005) else color(.985,.003)
        val ink = if (soft) color(.86,.005,248.0) else if (dark) color(.96,.003) else color(.18,.01)
        val subtle = if (soft) color(.52,.008,248.0) else color(if (dark) .55 else .62,.008)
        val accent = AccentColors.accent(context,dark,soft)
        val reduced = Settings.Global.getFloat(context.contentResolver,Settings.Global.ANIMATOR_DURATION_SCALE,1f) == 0f
        val bars = ViewCompat.getRootWindowInsets(this)?.getInsets(WindowInsetsCompat.Type.systemBars())
        val top = (height+(bars?.top ?: 0)-(bars?.bottom ?: 0)-129*density)/2
        canvas.drawColor(bg)
        paint.color = subtle; paint.style = Paint.Style.FILL; paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create("monospace",Typeface.NORMAL); paint.textSize = 11*density
        // CSS letter-spacing: .06em (UILabel kern on iOS).
        val caption = context.getString(R.string.loader_caption)
        val spacing = .66f*density
        var textX = (width-paint.measureText(caption)-spacing*(caption.length-1))/2
        paint.textAlign = Paint.Align.LEFT
        for (letter in caption) {
            val glyph = letter.toString()
            canvas.drawText(glyph,textX,top+118*density-paint.fontMetrics.ascent,paint)
            textX += paint.measureText(glyph)+spacing
        }
        canvas.save(); canvas.translate((width-96*density)/2,top); canvas.scale(2*density,2*density)
        val pulse = if (reduced) (1-.55*(1-cos(phase(1.4)*2*Math.PI))/2).toFloat() else 1f
        fun brush(color: Int, stroke: Float = 0f, alpha: Float = 1f) {
            paint.color = color; paint.alpha = (255*alpha*pulse).toInt().coerceIn(0,255)
            paint.style = if (stroke == 0f) Paint.Style.FILL else Paint.Style.STROKE
            paint.strokeWidth = stroke; paint.strokeCap = Paint.Cap.ROUND; paint.strokeJoin = Paint.Join.ROUND
        }
        canvas.save(); canvas.clipPath(clip); canvas.translate(if (reduced) 0f else -12+12*phase(1.4),29f)
        brush(accent); canvas.drawPath(wave,paint); canvas.restore()
        if (!reduced) for ((x,y,r,delay,dx) in bubbles) {
            val p = phase(1.4,delay); val move = bubbleEase.getInterpolation(p)
            val alpha = if (p < .12f) bubbleEase.getInterpolation(p/.12f) else if (p < .75f) 1f else 1-bubbleEase.getInterpolation((p-.75f)/.25f)
            brush(accent,alpha=alpha); canvas.drawCircle(x+dx*move,y-36*move,r,paint)
            brush(bg,1.1f,alpha); canvas.drawCircle(x+dx*move,y-36*move,r,paint)
        }
        brush(ink,3.4f); canvas.drawPath(glass,paint); canvas.drawPath(cap,paint)
        if (!reduced) for (i in 0..2) {
            val p = phase(1.8,i*.45f)
            val alpha = if (p < .35f) .7f*steamEase.getInterpolation(p/.35f) else .7f*(1-steamEase.getInterpolation((p-.35f)/.65f))
            canvas.save(); canvas.translate(0f,3-12*steamEase.getInterpolation(p))
            brush(ink,2f,alpha); canvas.drawPath(steam[i],paint); canvas.restore()
        }
        canvas.restore()
        if (isShown) postInvalidateOnAnimation()
    }
    override fun onVisibilityAggregated(isVisible: Boolean) { super.onVisibilityAggregated(isVisible); if (isVisible) invalidate() }
}
