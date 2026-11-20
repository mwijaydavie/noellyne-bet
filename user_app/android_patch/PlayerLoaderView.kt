package com.example.football_viewer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SweepGradient
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Centered broadcast loader: rotating coral sweep arc, one expanding radar
 * ring, and a caption underneath. Drawn on a private ticker so the activity
 * never rebuilds its view tree while buffering.
 */
class PlayerLoaderView(context: Context) : LinearLayout(context) {

    private val arc = ArcView(context)
    private val caption = TextView(context)

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER
        visibility = View.GONE
        isClickable = false
        addView(arc, LayoutParams(dp(62), dp(62)))
        caption.apply {
            textSize = 10.5f
            letterSpacing = 0.03f
            setTextColor(Color.rgb(244, 162, 140))
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
            maxLines = 2
        }
        addView(caption)
    }

    fun show(text: String) {
        caption.text = text
        if (visibility != VISIBLE) visibility = VISIBLE
        arc.start()
    }

    fun hide() {
        visibility = GONE
        arc.stop()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private class ArcView(context: Context) : View(context) {

        private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 3f
            strokeCap = Paint.Cap.ROUND
        }
        private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.4f
        }
        private var angle = 0f
        private var ring = 0f
        private val rect = RectF()

        private val ticker = object : Runnable {
            override fun run() {
                angle = (angle + 4.5f) % 360f
                ring += 0.018f
                if (ring > 1f) ring = 0f
                invalidate()
                postDelayed(this, 16L)
            }
        }

        fun start() {
            removeCallbacks(ticker)
            post(ticker)
        }

        fun stop() = removeCallbacks(ticker)

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val radius = minOf(cx, cy) - dpLocal(6)
            if (radius <= 0f) return

            ringPaint.color = Color.argb(
                (52 * (1f - ring)).toInt().coerceIn(0, 52), 244, 162, 140
            )
            canvas.drawCircle(cx, cy, radius * (0.5f + 0.5f * ring), ringPaint)

            rect.set(cx - radius, cy - radius, cx + radius, cy + radius)
            arcPaint.shader = SweepGradient(
                cx, cy,
                intArrayOf(
                    Color.TRANSPARENT,
                    Color.rgb(244, 151, 126),
                    Color.rgb(232, 130, 103)
                ),
                floatArrayOf(0f, 0.55f, 1f)
            )
            canvas.save()
            canvas.rotate(angle, cx, cy)
            canvas.drawArc(rect, 0f, 250f, false, arcPaint)
            canvas.restore()
        }

        private fun dpLocal(value: Int): Float =
            value * resources.displayMetrics.density
    }
}
