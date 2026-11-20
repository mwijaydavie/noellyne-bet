package com.example.football_viewer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View
import kotlin.math.abs
import kotlin.math.sin

/**
 * Coral equalizer used by the player's audio-only stage.
 *
 * Five rounded bars breathe on a sine wave, drawn in a single `onDraw` and
 * re-posted every 60ms — no allocations per frame, no layout passes, so it
 * costs nothing next to video decoding (which is switched off in this mode).
 */
class AudioStageView(context: Context) : View(context) {

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(232, 130, 103)
    }

    private val softPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(46, 244, 162, 140)
    }

    private var phase = 0f
    private val barCount = 5
    private val rect = RectF()

    fun setActive(active: Boolean) {
        if (active) {
            phase = 0f
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val widthPx = width.toFloat()
        val heightPx = height.toFloat()
        if (widthPx <= 0f || heightPx <= 0f) return

        val gap = widthPx * 0.05f
        val barWidth = (widthPx - gap * (barCount - 1)) / barCount

        // Ambient halo behind the bars.
        canvas.drawRoundRect(
            RectF(0f, heightPx * 0.42f, widthPx, heightPx * 0.58f),
            heightPx * 0.08f,
            heightPx * 0.08f,
            softPaint
        )

        for (index in 0 until barCount) {
            val wave = abs(sin(phase + index * 0.62f))
            val barHeight = heightPx * (0.26f + 0.74f * wave)
            val left = index * (barWidth + gap)
            val top = (heightPx - barHeight) / 2f
            rect.set(left, top, left + barWidth, top + barHeight)
            canvas.drawRoundRect(rect, barWidth / 2f, barWidth / 2f, barPaint)
        }

        phase += 0.16f
        if (phase > 1000f) phase = 0f
        if (isAttachedToWindow && visibility == VISIBLE) {
            postInvalidateDelayed(60)
        }
    }
}
