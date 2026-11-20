package com.example.football_viewer

import android.app.Activity
import android.app.AlertDialog
import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.ClipDrawable
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.TextUtils
import android.util.Base64
import android.util.Rational
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.SeekBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import java.net.URI
import java.lang.ref.WeakReference
import java.util.Locale

// Uses elapsed time only while playback is expected. Seeking, pausing and
// backgrounding reset the progress baseline rather than consuming a deadline.
internal class PlaybackProgressWatchdog(
    private val startupTimeoutMs: Long = 20000L,
    private val progressTimeoutMs: Long = 25000L
) {
    var started = false
        private set
    private var lastProgressAt = 0L
    private var lastPosition = 0L
    private var initialized = false

    fun resetBaseline(now: Long, position: Long) {
        initialized = true
        lastProgressAt = now
        lastPosition = position
    }

    fun rendered(now: Long, position: Long) {
        started = true
        resetBaseline(now, position)
    }

    fun stalledForMs(now: Long): Long = (now - lastProgressAt).coerceAtLeast(0L)

    // Positive position changes are progress only after discontinuity listeners
    // have reset the baseline; a seek itself must never count as a first frame.
    fun sample(now: Long, position: Long, active: Boolean): Boolean {
        if (!initialized || !active) {
            resetBaseline(now, position)
            return false
        }
        if (position > lastPosition) {
            started = true
            lastProgressAt = now
        } else if (position < lastPosition) {
            lastProgressAt = now
        }
        lastPosition = position
        val timeout = if (started) progressTimeoutMs else startupTimeoutMs
        return now - lastProgressAt >= timeout
    }
}

@UnstableApi
class NativePlayerActivity : Activity() {
    companion object {
        private var activePlayer = WeakReference<NativePlayerActivity>(null)
        private val sourceSessions = PlaybackSourceSessions()

        fun prepareOpeningSession(sessionId: String) {
            sourceSessions.begin(sessionId)
        }

        fun cancelOpeningSession(sessionId: String) {
            sourceSessions.close(sessionId)
        }

        fun appendSources(sessionId: String, json: String): Boolean {
            if (sessionId.isBlank() || json.isBlank() || !sourceSessions.isCurrent(sessionId)) return false
            val activity = activePlayer.get()
            if (activity == null || sessionId != activity.sessionId ||
                activity.isFinishing || activity.isDestroyed) {
                return sourceSessions.enqueueIfOpening(sessionId, json)
            }
            activity.runOnUiThread {
                if (activePlayer.get() === activity && sessionId == activity.sessionId &&
                    sourceSessions.isCurrent(sessionId) && !activity.isFinishing && !activity.isDestroyed) {
                    activity.appendSessionSources(json)
                }
            }
            return true
        }
    }

    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private lateinit var playerView: PlayerView
    private lateinit var videoHost: FrameLayout
    private lateinit var topBar: LinearLayout
    private var controlsVisible = true
    private var controlsHideRunnable: Runnable? = null
    private val controlsHideDelayMs = 7000L
    private lateinit var qualityButton: TextView
    private lateinit var settingsButton: TextView
    private lateinit var serverButton: TextView
    private lateinit var serverRail: LinearLayout
    private lateinit var serverRailScroll: HorizontalScrollView
    private lateinit var statusText: TextView
    private lateinit var playerLoader: PlayerLoaderView
    private lateinit var heroControls: LinearLayout
    private lateinit var heroPlay: TextView
    private lateinit var topScrim: View
    private lateinit var bottomScrim: View
    private lateinit var playerDock: LinearLayout
    private lateinit var compactControls: LinearLayout
    private lateinit var compactPlay: TextView
    private lateinit var compactTime: TextView
    private lateinit var compactSeek: SeekBar
    private lateinit var displayModeButton: TextView
    private lateinit var audioStage: LinearLayout
    private var audioOnlyMode = false
    private lateinit var theatrePanel: ScrollView
    private lateinit var theatreBody: LinearLayout
    private lateinit var settingsPanel: LinearLayout
    private lateinit var settingsScroll: ScrollView
    private lateinit var settingsItems: LinearLayout
    private var settingsSection = "video"
    private var selectedAudioLabel: String? = null
    private var selectedSubtitleLabel: String? = null
    private var displayMode = 0 // 0=Fit, 1=Full, 2=Zoom
    private var displayCutoutSafeRight = 0 // Control inset only, never video.

    private var sources = JSONArray()
    private val routeOverrides = mutableMapOf<Int, String>()
    private var selectedServerIndex = 0
    private var matchId = ""
    private var sessionId = ""
    private var qualityOptions = mutableListOf<QualityOption>()
    private var forcedQualityLabel: String? = null
    private var autoFallbackTried = mutableSetOf<Int>()
    private var pendingFallback: Runnable? = null
    private var progressCheck: Runnable? = null
    private var playbackGeneration = 0
    private var activityResumed = false
    private var progressWatchdog = PlaybackProgressWatchdog()
    private var sameLineRecoveryUsed = false
    private var openingStartedAt = 0L
    private var startedReported = false
    private var bufferingStartedAt: Long? = null
    private var bufferingPhase = "startup"
    private var suspendedAt: Long? = null

    private data class QualityOption(
        val label: String,
        val group: Tracks.Group,
        val trackIndex: Int,
        val height: Int,
        val bitrate: Int
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // The fullscreen Media3 player must be allowed to paint behind the
        // punch-hole camera. Resizing the PlayerView to Full/Zoom alone cannot
        // fill a system-reserved display-cutout strip. Do this before creating
        // the root view so Android measures the video against the full window.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                        else
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
        } catch (_: Throwable) {
            // An OEM that rejects the optional window layout must not stop playback.
        }

        try {
            createPlayerScreen()
        } catch (t: Throwable) {
            val detail = buildString {
                append("Player UI failed")
                append("\n")
                append(t.javaClass.simpleName)
                val message = t.message?.trim().orEmpty()
                if (message.isNotEmpty()) {
                    append(": ")
                    append(message.take(180))
                }
            }
            showFatalError(detail)
        }
    }

    private fun emitPlaybackEvent(
        event: String,
        extra: Map<String, Any?> = emptyMap()
    ) {
        val source = sources.optJSONObject(selectedServerIndex)
        val streamType = when (source?.optString("streamType").orEmpty().lowercase(Locale.ROOT)) {
            "m3u8", "hls" -> "hls"
            "mpd", "dash" -> "dash"
            "mp4" -> "mp4"
            "flv" -> "flv"
            "auto", "" -> "auto"
            else -> "unknown"
        }
        val resolution = source?.optString("resolution").orEmpty().lowercase(Locale.ROOT)
        val healthStatus = source?.optString("healthStatus").orEmpty().lowercase(Locale.ROOT)
        val base = mutableMapOf<String, Any?>(
            "selected_index" to selectedServerIndex,
            "line_count" to sources.length(),
            "stream_type" to streamType,
            "resolution" to if (resolution.matches(Regex("^(\\d{3,4}p|auto|hd|sd|fhd|uhd|4k)$"))) resolution else "unknown",
            "health_status" to if (healthStatus in setOf("healthy", "unknown", "slow", "failed")) healthStatus else "unknown"
        )
        if (matchId.matches(Regex("^[a-zA-Z0-9_:-]{1,128}$"))) {
            base["match_id"] = matchId
        }
        val lineId = sequenceOf("id", "lineId", "linkId")
            .map { source?.optString(it).orEmpty() }
            .firstOrNull { it.matches(Regex("^[a-zA-Z0-9_:-]{1,128}$")) }
        if (lineId != null) base["line_id"] = lineId
        // Never send protected paths, query tokens, headers or ClearKey values.
        val routeHost = try {
            URI(source?.optString("url").orEmpty())
                .takeIf { it.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") }
                ?.host?.lowercase(Locale.ROOT)
        } catch (_: Exception) { null }
        if (!routeHost.isNullOrBlank()) base["route"] = routeHost
        base.putAll(extra)
        MainActivity.emitPlayerEvent(event, base)
    }

    private fun createPlayerScreen() {
        // Parse the payload before doing any ExoPlayer work.
        matchId = intent.getStringExtra("matchId").orEmpty()
        sessionId = intent.getStringExtra("sessionId").orEmpty()
        val json = intent.getStringExtra("sourcesJson").orEmpty()
        if (json.isBlank()) {
            showFatalError("No stream source")
            return
        }

        sources = try {
            JSONArray(json)
        } catch (t: Throwable) {
            showFatalError("Invalid stream source")
            return
        }

        if (sources.length() == 0) {
            showFatalError("No stream source")
            return
        }
        if (sessionId.isNotBlank() && !sourceSessions.isCurrent(sessionId)) {
            finish()
            return
        }
        activePlayer = WeakReference(this)
        sourceSessions.register(sessionId)?.let { appendSessionSources(it) }

        selectedServerIndex = intent.getIntExtra("selectedIndex", 0)
            .coerceIn(0, sources.length() - 1)

        if (Build.VERSION.SDK_INT >= 33) {
            try {
                requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 91)
            } catch (_: Throwable) {
            }
        }

        val portraitStart = sources.optJSONObject(selectedServerIndex)?.optBoolean("portraitStart", false) == true
        // Start with the compact top-aligned portrait player; Rotate enters
        // full landscape playback. Preserve a manual turn across recreation.
        requestedOrientation = if (intent.getBooleanExtra("nca_landscape", false))
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT

        // Put a content view on screen first. Some Android 12 / OEM builds can
        // be fragile if immersive-window calls happen before a decor view exists.
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(20, 18, 18))
        }
        setContentView(root)

        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window.statusBarColor = Color.rgb(20, 18, 18)
            window.navigationBarColor = Color.rgb(20, 18, 18)
        } catch (_: Throwable) {
            // Window cosmetics must never stop playback from starting.
        }

        playerView = PlayerView(this).apply {
            setBackgroundColor(Color.rgb(20, 18, 18))
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            // Native Media3 default controls are oversized and show unwanted
            // Previous / Next buttons. Use one slim, accessible transport row.
            useController = false
        }
        // The player controls and progress/time belong to the VIDEO box, not
        // the bottom of an otherwise empty portrait phone screen.
        videoHost = FrameLayout(this).apply { setBackgroundColor(Color.rgb(20, 18, 18)) }
        videoHost.addView(playerView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(videoHost, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL))

        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(7), dp(4), dp(7), dp(4))
            setBackgroundColor(Color.rgb(29, 25, 24))
            // Server name / quality / back button stay hidden until player
            // controls are shown by a tap.
            visibility = View.GONE
        }

        val back = overlayButton("←").apply {
            textSize = 21f
            contentDescription = "Back"
            setOnClickListener {
                emitPlaybackEvent("playback closed")
                finish()
            }
        }

        val safeTitle = intent.getStringExtra("title")
            .orEmpty()
            .trim()
            .take(120)
            .ifEmpty { "Football Live" }
        val titleText = TextView(this).apply {
            text = safeTitle
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), 0, dp(6), 0)
            contentDescription = "Match: $safeTitle"
        }

        serverButton = overlayButton("≡").apply {
            textSize = 19f
            maxWidth = dp(38)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(4), 0, dp(4), 0)
            contentDescription = "Show all lines"
            setOnClickListener { showServerMenu() }
        }

        qualityButton = overlayButton("Auto").apply {
            textSize = 14f
            setPadding(dp(12), 0, dp(12), 0)
            setOnClickListener { openSettingsMenu("video") }
        }

        displayModeButton = overlayButton("Fit").apply {
            contentDescription = "Original aspect ratio; tap for Full"
            textSize = 11f
            setPadding(dp(2), 0, dp(2), 0)
            setOnClickListener { toggleDisplayMode(); setControlsVisible(true) }
        }

        val rotateButton = overlayButton("↻").apply {
            contentDescription = "Rotate video"
            setOnClickListener {
                val landscape = resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
                intent.putExtra("nca_landscape", landscape)
                requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                setControlsVisible(true)
            }
        }
        if (visibleServerIndices().size == 1) serverButton.visibility = View.GONE
        topBar.addView(back, LinearLayout.LayoutParams(dp(36), dp(36)))
        topBar.addView(
            titleText,
            LinearLayout.LayoutParams(0, dp(36), 1f)
        )
        topBar.addView(
            displayModeButton,
            LinearLayout.LayoutParams(
                dp(34),
                dp(34)
            )
        )

        val miniButton = overlayButton("⤡").apply {
            contentDescription = "Play in mini player"
            setOnClickListener { enterMiniPlayer() }
        }
        val audioButton = overlayButton("\u266A").apply {
            contentDescription = "Audio only mode"
            setOnClickListener { setAudioOnly(!audioOnlyMode) }
        }
        topBar.addView(audioButton, LinearLayout.LayoutParams(dp(36), dp(36)))
        topBar.addView(miniButton, LinearLayout.LayoutParams(dp(36), dp(36)))
        topBar.addView(rotateButton, LinearLayout.LayoutParams(dp(36), dp(36)))

        root.addView(
            topBar,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        )

        serverRail = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(7), dp(2), dp(7), dp(2))
        }
        serverRailScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setBackgroundColor(Color.TRANSPARENT)
            addView(
                serverRail,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
            visibility = View.GONE
        }
        // Rail belongs INSIDE the picture, above the transport controls:
        // hiding it cannot leave a black strip or reduce fullscreen video.
        videoHost.addView(
            serverRailScroll,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(45), Gravity.BOTTOM).apply {
                bottomMargin = dp(36)
            }
        )
        // One compact transport row. No Previous/Next server shortcuts.
        compactControls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), 0, dp(4), 0)
            setBackgroundColor(Color.argb(90, 0, 0, 0))
            visibility = View.GONE
        }
        fun transportButton(label: String, description: String): TextView =
            TextView(this).apply {
                text = label
                contentDescription = description
                textSize = 12f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 0)
                background = null
            }
        val rewind = transportButton("↶5", "Back 5 seconds").apply {
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                exo.seekTo((exo.currentPosition - 5000L).coerceAtLeast(0L))
                updateCompactControls()
                setControlsVisible(true)
            }
        }
        compactPlay = transportButton("Ⅱ", "Play or pause").apply {
            textSize = 16f
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                if (exo.isPlaying) exo.pause() else exo.play()
                updateCompactControls()
                setControlsVisible(true)
            }
        }
        val forward = transportButton("15↷", "Forward 15 seconds").apply {
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                val max = exo.duration
                val target = exo.currentPosition + 15000L
                exo.seekTo(if (max != C.TIME_UNSET && max > 0) target.coerceAtMost(max) else target)
                updateCompactControls()
                setControlsVisible(true)
            }
        }
        compactTime = transportButton("LIVE", "Playback time").apply {
            textSize = 10f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setSingleLine(true)
            setPadding(dp(2), 0, dp(2), 0)
            maxWidth = dp(110)
        }
        compactSeek = SeekBar(this).apply {
            max = 1000
            progress = 0
            // A 3dp line + 10dp thumb, never a huge green filled rectangle.
            val track = GradientDrawable().apply {
                cornerRadius = dp(2).toFloat()
                setSize(dp(100), dp(3))
                setColor(Color.rgb(115, 106, 102))
            }
            val filledTrack = GradientDrawable().apply {
                cornerRadius = dp(2).toFloat()
                setSize(dp(100), dp(3))
                setColor(Color.rgb(244, 151, 126))
            }
            progressDrawable = LayerDrawable(arrayOf(
                track, ClipDrawable(filledTrack, Gravity.LEFT, ClipDrawable.HORIZONTAL)
            )).apply {
                setId(0, android.R.id.background)
                setId(1, android.R.id.progress)
                // Intrinsic size does not constrain the SeekBar layer bounds.
                for (layer in 0..1) {
                    setLayerHeight(layer, dp(3))
                    setLayerGravity(layer, Gravity.CENTER_VERTICAL)
                }
            }
            thumb = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setSize(dp(10), dp(10))
                setColor(Color.WHITE)
            }
            splitTrack = false
            setPadding(dp(2), 0, dp(2), 0)
            contentDescription = "Seek video"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, value: Int, fromUser: Boolean) {}
                override fun onStartTrackingTouch(seekBar: SeekBar?) {
                    controlsHideRunnable?.let { playerView.removeCallbacks(it) }
                }
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    val exo = player
                    val duration = exo?.duration ?: C.TIME_UNSET
                    if (exo != null && duration != C.TIME_UNSET && duration > 0) {
                        exo.seekTo(duration * progress / 1000L)
                    }
                    setControlsVisible(true)
                }
            })
        }
        settingsButton = overlayButton("⚙").apply {
            textSize = 18f
            background = null
            visibility = View.VISIBLE
            contentDescription = "Resolution audio and playback speed"
            setOnClickListener { showPlaybackSettings(); setControlsVisible(true) }
        }
        for (view in listOf(rewind, compactPlay, forward)) {
            compactControls.addView(view, LinearLayout.LayoutParams(dp(35), dp(35)))
        }
        compactControls.addView(compactTime, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dp(35)))
        compactControls.addView(compactSeek, LinearLayout.LayoutParams(0, dp(35), 1f))
        compactControls.addView(settingsButton, LinearLayout.LayoutParams(dp(35), dp(35)))
        fun frostedCircle(label: String, sizeDp: Int, description: String): TextView =
            TextView(this).apply {
                text = label
                contentDescription = description
                textSize = if (sizeDp >= 56) 20f else 11f
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.argb(120, 0, 0, 0))
                    setStroke(dp(1), Color.argb(40, 255, 255, 255))
                }
                isClickable = true
                isFocusable = true
            }

        fun seekBy(deltaMs: Long) {
            val exo = player ?: return
            val max = exo.duration
            var target = exo.currentPosition + deltaMs
            if (target < 0L) target = 0L
            if (max != C.TIME_UNSET && max > 0L) target = target.coerceAtMost(max)
            exo.seekTo(target)
            updateCompactControls()
            setControlsVisible(true)
        }

        val rewindHero = frostedCircle("\u221210", 46, "Back 10 seconds").apply {
            setOnClickListener { seekBy(-10_000L) }
        }
        heroPlay = frostedCircle("\u2161", 58, "Play or pause").apply {
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                if (exo.isPlaying) exo.pause() else exo.play()
                updateCompactControls()
                setControlsVisible(true)
            }
        }
        val forwardHero = frostedCircle("+10", 46, "Forward 10 seconds").apply {
            setOnClickListener { seekBy(10_000L) }
        }
        heroControls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            visibility = View.GONE
        }
        heroControls.addView(rewindHero, LinearLayout.LayoutParams(dp(46), dp(46)))
        heroControls.addView(heroPlay, LinearLayout.LayoutParams(dp(58), dp(58)).apply {
            leftMargin = dp(26)
            rightMargin = dp(26)
        })
        heroControls.addView(forwardHero, LinearLayout.LayoutParams(dp(46), dp(46)))
        videoHost.addView(heroControls, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))

        videoHost.addView(compactControls, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(35), Gravity.BOTTOM
        ))
        val ticker = object : Runnable {
            override fun run() {
                if (isFinishing || isDestroyed) return
                updateCompactControls()
                playerView.postDelayed(this, 450L)
            }
        }
        playerView.post(ticker)
        fun layoutPlayer() {
            if (root.width <= 0 || root.height <= 0) return
            val landscape = root.width > root.height
            val hasLines = visibleServerIndices().size > 1
            val portraitHeight = (root.width * 9f / 16f).toInt()
                .coerceAtMost(root.height.coerceAtLeast(dp(120)))
            // Both orientation modes paint picture TOP; topbar and rail are
            // overlays. Neither reserves black layout space when hidden.
            topBar.layoutParams = (topBar.layoutParams as FrameLayout.LayoutParams).apply {
                gravity = Gravity.TOP
                topMargin = 0
            }
            topBar.background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.argb(192, 0, 0, 0), Color.argb(24, 0, 0, 0))
            )
            topBar.visibility = if (controlsVisible) View.VISIBLE else View.GONE
            // Portrait: leave the status bar alone and hang the picture from
            // its bottom edge, like a video page rather than a full-bleed app.
            val topInset = if (landscape) 0 else statusBarHeightPx()
            videoHost.layoutParams = (videoHost.layoutParams as FrameLayout.LayoutParams).apply {
                width = ViewGroup.LayoutParams.MATCH_PARENT
                height = if (landscape) root.height else portraitHeight
                gravity = Gravity.TOP
                topMargin = topInset
            }
            serverRailScroll.layoutParams =
                (serverRailScroll.layoutParams as FrameLayout.LayoutParams).apply {
                    width = ViewGroup.LayoutParams.MATCH_PARENT
                    height = dp(45)
                    gravity = Gravity.BOTTOM
                    bottomMargin = dp(36)
                }
            serverRailScroll.visibility = if (hasLines && controlsVisible) View.VISIBLE else View.GONE
            if (::theatrePanel.isInitialized) {
                theatrePanel.layoutParams = (theatrePanel.layoutParams as FrameLayout.LayoutParams).apply {
                    width = ViewGroup.LayoutParams.MATCH_PARENT
                    height = ViewGroup.LayoutParams.MATCH_PARENT
                    gravity = Gravity.TOP
                    topMargin = if (landscape) 0 else portraitHeight + topInset
                }
                theatrePanel.visibility = if (landscape) View.GONE else View.VISIBLE
            }
            if (::playerDock.isInitialized) {
                playerDock.visibility = if (landscape) View.GONE else View.VISIBLE
            }
            if (::settingsPanel.isInitialized) positionSettingsPanel(root, landscape)
        }
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> layoutPlayer() }
        root.post { layoutPlayer(); applyDisplayMode() }
        renderServerRail()

        // Single tap toggles the chrome, double tap seeks like YouTube.
        val gestures = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (::settingsPanel.isInitialized && settingsPanel.visibility == View.VISIBLE) {
                    closeSettingsMenu()
                    setControlsVisible(true)
                } else {
                    setControlsVisible(!controlsVisible)
                }
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                val half = (playerView.width / 2).toFloat()
                if (e.x < half) seekBy(-10_000L) else seekBy(10_000L)
                return true
            }
        })
        playerView.setOnTouchListener { _, event ->
            gestures.onTouchEvent(event)
            true
        }
        playerView.post { setControlsVisible(true) }

        statusText = TextView(this).apply {
            setTextColor(Color.rgb(244, 162, 140))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(dp(18), dp(11), dp(18), dp(11))
            letterSpacing = 0.02f
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                cornerRadius = dp(999).toFloat()
                setColor(Color.argb(200, 29, 25, 24))
                setStroke(dp(1), Color.argb(90, 232, 130, 103))
            }
            visibility = View.GONE
        }

        // Dead-centre broadcast loader (rotating coral arc + radar ring).
        playerLoader = PlayerLoaderView(this)
        videoHost.addView(
            playerLoader,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )

        // Gradient scrims keep titles and controls legible over bright frames.
        topScrim = View(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.argb(184, 0, 0, 0), Color.TRANSPARENT)
            )
            visibility = View.GONE
        }
        bottomScrim = View(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                intArrayOf(Color.argb(210, 0, 0, 0), Color.TRANSPARENT)
            )
            visibility = View.GONE
        }
        videoHost.addView(topScrim, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(96), Gravity.TOP
        ))
        videoHost.addView(bottomScrim, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(112), Gravity.BOTTOM
        ))

        // Audio-only stage: video decoding is switched off, the picture area
        // becomes a coral equalizer so data and battery are saved.
        audioStage = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(11, 10, 10))
            visibility = View.GONE
        }
        audioStage.addView(AudioStageView(this), LinearLayout.LayoutParams(
            dp(150), dp(58)
        ))
        audioStage.addView(TextView(this).apply {
            text = "AUDIO MODE \u00B7 SAVING DATA"
            textSize = 9.5f
            letterSpacing = 0.16f
            setTextColor(Color.rgb(232, 130, 103))
            setPadding(0, dp(14), 0, dp(14))
        })
        audioStage.addView(TextView(this).apply {
            text = "Back to video"
            textSize = 12f
            setTextColor(Color.rgb(245, 239, 234))
            setPadding(dp(18), dp(9), dp(18), dp(9))
            background = GradientDrawable().apply {
                cornerRadius = dp(999).toFloat()
                setColor(Color.argb(255, 35, 32, 32))
                setStroke(dp(1), Color.argb(90, 232, 130, 103))
            }
            setOnClickListener { setAudioOnly(false) }
        })
        videoHost.addView(audioStage, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        // Portrait companion panel: the 16:9 picture stays pinned to the top
        // and everything below it becomes the Match Theatre.
        buildTheatrePanel(root)
        buildDock(root)

        // Web-style settings are a dark native overlay, not Android PopupMenu.
        // Add last so the panel remains above playback/status without replacing Media3.
        buildSettingsPanel(root)

        // The VIDEO stays truly edge-to-edge. Only tappable chrome is moved
        // away from cutout pixels, so a left/right camera hole cannot cover
        // Back, Fit/Full/Zoom, transport or the selected line controls.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            root.setOnApplyWindowInsetsListener { _, insets ->
                val cutout = insets.displayCutout
                val landscape = resources.configuration.orientation ==
                    Configuration.ORIENTATION_LANDSCAPE
                val safeLeft = if (landscape) cutout?.safeInsetLeft ?: 0 else 0
                val safeRight = if (landscape) cutout?.safeInsetRight ?: 0 else 0
                val safeTop = if (!landscape) cutout?.safeInsetTop ?: 0 else 0
                topBar.setPadding(dp(7) + safeLeft, dp(4) + safeTop,
                    dp(7) + safeRight, dp(4))
                compactControls.setPadding(dp(4) + safeLeft, 0,
                    dp(4) + safeRight, 0)
                serverRail.setPadding(dp(7) + safeLeft, dp(2),
                    dp(7) + safeRight, dp(2))
                // Settings are anchored to END; keep their close control
                // visible if the camera cutout sits on the right instead.
                displayCutoutSafeRight = safeRight
                if (::settingsPanel.isInitialized && root.width > 0) {
                    positionSettingsPanel(root, landscape)
                }
                insets
            }
            root.requestApplyInsets()
        }

        // Run immersive-mode and playback only after the view hierarchy exists.
        root.post {
            safeHideSystemBars()
            root.requestApplyInsets()
            playServer(selectedServerIndex)
            // Keep audio alive if the viewer locks the screen or leaves.
            PlaybackAudioService.start(
                this,
                intent.getStringExtra("title").orEmpty().ifBlank { "Noellyne Bet" },
                "Live stream"
            )
        }
    }

    /**
     * Headphones mode: keep the stream audio and the foreground service alive
     * while the video surface is released, exactly like YouTube's audio-only
     * playback.
     */
    private fun setAudioOnly(enabled: Boolean) {
        audioOnlyMode = enabled
        applyAudioOnlyTracks(enabled)
        if (::playerView.isInitialized) {
            playerView.visibility = if (enabled) View.INVISIBLE else View.VISIBLE
        }
        if (::audioStage.isInitialized) {
            audioStage.visibility = if (enabled) View.VISIBLE else View.GONE
            for (index in 0 until audioStage.childCount) {
                val child = audioStage.getChildAt(index)
                if (child is AudioStageView) child.setActive(enabled)
            }
        }
        if (enabled) {
            PlaybackAudioService.start(
                this,
                intent.getStringExtra("title").orEmpty().ifBlank { "Noellyne Bet" },
                "Audio only \u00B7 saving data"
            )
        }
        setControlsVisible(true)
    }

    /**
     * Hiding a PlayerView does NOT stop ExoPlayer from downloading video
     * segments. Disabling the video track type does, and clearing the surface
     * releases the decoder. Muxed single-rendition streams lose their audio
     * when video is disabled, so that case re-enables the track but keeps the
     * surface detached (GPU decode stops, audio survives).
     */
    private fun applyAudioOnlyTracks(enabled: Boolean) {
        val exo = player ?: return
        try {
            if (enabled) {
                exo.trackSelectionParameters = exo.trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true)
                    .build()
                exo.clearVideoSurface()
                // Re-check shortly: if the stream was muxed, audio would drop.
                playerView.postDelayed({
                    val current = player
                    if (current != null && audioOnlyMode) {
                        val hasAudio = current.currentTracks.groups.any { group ->
                            group.type == C.TRACK_TYPE_AUDIO && group.isSupported
                        }
                        if (!hasAudio) {
                            current.trackSelectionParameters =
                                current.trackSelectionParameters
                                    .buildUpon()
                                    .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                                    .build()
                            current.clearVideoSurface()
                        }
                    }
                }, 1200L)
            } else {
                exo.trackSelectionParameters = exo.trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                    .build()
                if (::playerView.isInitialized) {
                    (playerView.videoSurfaceView as? SurfaceView)?.let { surface ->
                        exo.setVideoSurfaceView(surface)
                    }
                }
            }
        } catch (_: Throwable) {
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Leaving the app (home / recents) drops into the floating mini player
        // instead of killing playback.
        if (::playerView.isInitialized) enterMiniPlayer()
    }

    private fun enterMiniPlayer() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Throwable) {
            // OEMs without PiP support simply stay full screen.
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            if (::theatrePanel.isInitialized) theatrePanel.visibility = View.GONE
            if (::playerDock.isInitialized) playerDock.visibility = View.GONE
            setControlsVisible(false)
        } else {
            setControlsVisible(true)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) safeHideSystemBars()
    }

    private fun clearControlsHideTimer() {
        if (!::playerView.isInitialized) return
        controlsHideRunnable?.let { playerView.removeCallbacks(it) }
        controlsHideRunnable = null
    }

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        if (::topBar.isInitialized)
            topBar.visibility = if (visible) View.VISIBLE else View.GONE
        if (::compactControls.isInitialized)
            compactControls.visibility = if (visible) View.VISIBLE else View.GONE
        if (::serverRailScroll.isInitialized)
            serverRailScroll.visibility =
                if (visible && visibleServerIndices().size > 1) View.VISIBLE else View.GONE
        if (::heroControls.isInitialized)
            heroControls.visibility = if (visible) View.VISIBLE else View.GONE
        if (::topScrim.isInitialized)
            topScrim.visibility = if (visible) View.VISIBLE else View.GONE
        if (::bottomScrim.isInitialized)
            bottomScrim.visibility = if (visible) View.VISIBLE else View.GONE
        clearControlsHideTimer()
        if (visible && ::playerView.isInitialized) {
            val task = Runnable {
                if (!isFinishing && !isDestroyed &&
                    (!::settingsPanel.isInitialized ||
                     settingsPanel.visibility != View.VISIBLE)) {
                    setControlsVisible(false)
                }
            }
            controlsHideRunnable = task
            playerView.postDelayed(task, controlsHideDelayMs)
        }
    }

    private fun updateCompactControls() {
        if (!::compactControls.isInitialized) return
        val exo = player ?: return
        compactPlay.text = if (exo.isPlaying) "Ⅱ" else "▶"
        val duration = exo.duration
        val position = exo.currentPosition.coerceAtLeast(0)
        fun time(milliseconds: Long): String {
            val seconds = milliseconds.coerceAtLeast(0) / 1000
            return if (seconds >= 3600) String.format(
                Locale.US, "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60
            ) else String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60)
        }
        if (duration == C.TIME_UNSET || duration <= 0) {
            compactTime.text = "● LIVE"
            compactSeek.isEnabled = false
            compactSeek.progress = 0
        } else {
            compactTime.text = "${time(position)} / ${time(duration)}"
            compactSeek.isEnabled = true
            compactSeek.progress = ((position * 1000L) / duration).toInt().coerceIn(0, 1000)
        }
    }

    private fun playServer(index: Int, recoveringSameLine: Boolean = false) {
        if (index !in 0 until sources.length()) return
        pendingFallback?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        pendingFallback = null
        stopProgressCheck()
        playbackGeneration += 1
        selectedServerIndex = index
        renderServerRail()
        val source = sources.optJSONObject(index) ?: return
        val url = routeOverrides[index] ?: source.optString("url").trim()
        if (url.isBlank()) {
            tryNextServer("Empty stream URL")
            return
        }

        sameLineRecoveryUsed = recoveringSameLine
        progressWatchdog = PlaybackProgressWatchdog(
            startupTimeoutMs = if (hasPendingRoute(index)) 8000L else 20000L
        )
        openingStartedAt = SystemClock.elapsedRealtime()
        progressWatchdog.resetBaseline(openingStartedAt, 0L)
        startedReported = false
        bufferingStartedAt = null
        suspendedAt = if (activityResumed) null else openingStartedAt
        forcedQualityLabel = null
        selectedAudioLabel = null
        selectedSubtitleLabel = null
        closeSettingsMenu()
        qualityOptions.clear()
        qualityButton.text = "Auto"
        showStatus("Opening ${serverLabel(index)}…")

        playerView.player = null
        player?.release()
        player = null
        trackSelector = null

        try {
            val headers = mutableMapOf<String, String>()
            val referer = source.optString("referer").trim()
            val origin = source.optString("origin").trim()
            if (referer.isNotBlank()) headers["Referer"] = referer
            if (origin.isNotBlank()) headers["Origin"] = origin

            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(12000)
                .setReadTimeoutMs(15000)
                .setDefaultRequestProperties(headers)

            val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)
            val itemBuilder = MediaItem.Builder().setUri(url)
            when (source.optString("streamType", "auto").lowercase()) {
                "dash", "mpd" -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
                "hls", "m3u8" -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            }

            val keyId = source.optString("keyId").trim()
            val keyData = source.optString("keyData").trim()
            if (keyId.isNotBlank() && keyData.isNotBlank()) {
                val clearKeyJson = "{\"keys\":[{\"kty\":\"oct\",\"kid\":\"${toBase64Url(keyId)}\",\"k\":\"${toBase64Url(keyData)}\"}],\"type\":\"temporary\"}"
                val callback = LocalMediaDrmCallback(clearKeyJson.toByteArray(Charsets.UTF_8))
                val drm = DefaultDrmSessionManager.Builder()
                    .setPlayClearSamplesWithoutKeys(true)
                    .setMultiSession(false)
                    .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                    .build(callback)
                mediaSourceFactory.setDrmSessionManagerProvider { drm }
                itemBuilder.setDrmConfiguration(MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID).build())
            }

            val selector = DefaultTrackSelector(this)
            trackSelector = selector
            val exo = ExoPlayer.Builder(this)
                .setTrackSelector(selector)
                // Start after one second of media, then build a bounded live
                // buffer. Rebuffering still waits longer to absorb mobile jitter.
                .setLoadControl(DefaultLoadControl.Builder()
                    .setBufferDurationsMs(15000, 30000, 1000, 2500)
                    .build())
                .setMediaSourceFactory(mediaSourceFactory)
                .setAudioAttributes(AudioAttributes.DEFAULT, true)
                .setHandleAudioBecomingNoisy(true)
                .build()

            PlaybackAudioBridge.player = exo
            val generation = playbackGeneration
            fun currentPlayback() = generation == playbackGeneration && player === exo && pendingFallback == null &&
                !isFinishing && !isDestroyed

            exo.addListener(object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    if (!currentPlayback()) return
                    rebuildQualityOptions(tracks)
                }

                override fun onRenderedFirstFrame() {
                    if (!currentPlayback()) return
                    val active = activityResumed && exo.playWhenReady &&
                        exo.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE
                    updatePlaybackTiming(active)
                    progressWatchdog.rendered(SystemClock.elapsedRealtime(), exo.currentPosition)
                    if (active) reportPlaybackProgress()
                }

                override fun onPositionDiscontinuity(
                    oldPosition: Player.PositionInfo,
                    newPosition: Player.PositionInfo,
                    reason: Int
                ) {
                    if (!currentPlayback()) return
                    progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), exo.currentPosition)
                    lastSamplePosition = exo.currentPosition
                }

                override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                    if (!currentPlayback()) return
                    updatePlaybackTiming(activityResumed && playWhenReady)
                    progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), exo.currentPosition)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (!currentPlayback()) return
                    when (playbackState) {
                        Player.STATE_READY -> {
                            if (progressWatchdog.started) hideStatus()
                        }
                        Player.STATE_BUFFERING -> {
                            showStatus("Buffering…")
                            beginBuffering()
                        }
                        Player.STATE_ENDED -> {
                            showStatus("Stream ended")
                            emitPlaybackEvent("playback ended")
                            stopProgressCheck()
                            // Finite videos may end normally. Only a confirmed
                            // live timeline is recovered automatically.
                            if (activityResumed && exo.playWhenReady && exo.isCurrentMediaItemLive) {
                                recoverOrFallback("Live stream ended")
                            }
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    if (!currentPlayback()) return
                    emitPlaybackEvent(
                        "playback line failed",
                        mapOf("error_code" to error.errorCode)
                    )
                    tryNextServer("Server unavailable")
                }
            })

            player = exo
            playerView.player = exo
            exo.setMediaItem(itemBuilder.build())
            exo.prepare()
            exo.playWhenReady = true
            startProgressCheck(exo, generation)
        } catch (t: Throwable) {
            emitPlaybackEvent(
                "playback line failed",
                mapOf("error_code" to t.javaClass.simpleName)
            )
            tryNextServer("Server unavailable")
        }
    }

    private fun beginBuffering() {
        if (!activityResumed || player?.playWhenReady != true || bufferingStartedAt != null) return
        bufferingStartedAt = SystemClock.elapsedRealtime()
        bufferingPhase = if (startedReported) "rebuffer" else "startup"
        emitPlaybackEvent("playback buffering", mapOf("phase" to bufferingPhase))
    }

    private fun appendSessionSources(json: String) {
        val updated = try { JSONArray(json) } catch (_: Exception) { return }
        if (updated.length() <= sources.length()) return
        // Late backups can extend the chooser only. Keep the current player,
        // selection and existing source credentials unchanged.
        val identityFields = arrayOf("id", "lineId", "linkId", "url", "streamType", "referer", "origin", "keyId", "keyData")
        for (i in 0 until sources.length()) {
            val before = sources.optJSONObject(i) ?: return
            val after = updated.optJSONObject(i) ?: return
            if (identityFields.any { before.optString(it) != after.optString(it) }) return
        }
        val additions = mutableListOf<org.json.JSONObject>()
        for (i in sources.length() until updated.length()) {
            val source = updated.optJSONObject(i) ?: return
            if (source.optString("url").isBlank()) return
            additions.add(source)
        }
        additions.forEach { sources.put(it) }
        renderServerRail()
    }

    private fun reportPlaybackProgress() {
        val now = SystemClock.elapsedRealtime()
        if (!startedReported) {
            startedReported = true
            emitPlaybackEvent("playback started", mapOf("startup_ms" to (now - openingStartedAt).coerceAtLeast(0L)))
        }
        bufferingStartedAt?.let {
            emitPlaybackEvent("playback buffering ended", mapOf(
                "phase" to bufferingPhase,
                "buffering_ms" to (now - it).coerceAtLeast(0L)
            ))
            bufferingStartedAt = null
        }
        hideStatus()
    }

    private fun updatePlaybackTiming(active: Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (!active) {
            if (suspendedAt == null) suspendedAt = now
        } else {
            suspendedAt?.let {
                val inactiveMs = (now - it).coerceAtLeast(0L)
                openingStartedAt += inactiveMs
                bufferingStartedAt = bufferingStartedAt?.plus(inactiveMs)
            }
            suspendedAt = null
        }
    }

    private fun startProgressCheck(exo: ExoPlayer, generation: Int) {
        stopProgressCheck()
        val check = object : Runnable {
            override fun run() {
                if (generation != playbackGeneration || player !== exo || isFinishing || isDestroyed) return
                val active = activityResumed && exo.playWhenReady &&
                    exo.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE
                updatePlaybackTiming(active)
                val position = exo.currentPosition
                val beforeStarted = progressWatchdog.started
                val progressed = position > lastSamplePosition
                val timedOut = progressWatchdog.sample(SystemClock.elapsedRealtime(), position, active)
                lastSamplePosition = position
                if (active && progressWatchdog.started && (!beforeStarted || progressed)) reportPlaybackProgress()
                if (active && exo.playbackState == Player.STATE_BUFFERING) beginBuffering()
                if (active && progressWatchdog.started && progressWatchdog.stalledForMs(SystemClock.elapsedRealtime()) >= 2000L) {
                    beginBuffering()
                }
                if (active && timedOut) {
                    beginBuffering()
                    recoverOrFallback(if (startedReported) "Playback stalled" else "Stream startup timed out")
                    return
                }
                playerView.postDelayed(this, 1000L)
            }
        }
        lastSamplePosition = exo.currentPosition
        progressCheck = check
        playerView.postDelayed(check, 1000L)
    }

    private var lastSamplePosition = 0L

    private fun stopProgressCheck() {
        progressCheck?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        progressCheck = null
    }

    // A route is not a second line. Try it once for this line and session,
    // before marking the real stream failed or changing the chooser selection.
    private fun hasPendingRoute(index: Int): Boolean =
        !routeOverrides.containsKey(index) &&
            !sources.optJSONObject(index)?.optString("routeFallbackUrl").isNullOrBlank()

    private fun tryPlaybackRoute(): Boolean {
        val index = selectedServerIndex
        if (!hasPendingRoute(index)) return false
        val fallback = sources.optJSONObject(index)?.optString("routeFallbackUrl") ?: return false
        routeOverrides[index] = fallback
        emitPlaybackEvent("playback route fallback", mapOf("route" to "vercel"))
        playServer(index)
        return true
    }

    private fun recoverOrFallback(reason: String) {
        stopProgressCheck()
        if (tryPlaybackRoute()) return
        if (!sameLineRecoveryUsed) {
            emitPlaybackEvent("playback recovery", mapOf(
                "reason" to reason,
                "phase" to if (startedReported) "rebuffer" else "startup",
                "attempt" to 1
            ))
            showStatus("$reason • reconnecting…")
            playServer(selectedServerIndex, recoveringSameLine = true)
        } else {
            emitPlaybackEvent("playback line failed", mapOf(
                "error_code" to if (reason == "Live stream ended") "LIVE_STREAM_ENDED" else "PLAYBACK_PROGRESS_TIMEOUT",
                "phase" to if (startedReported) "rebuffer" else "startup"
            ))
            tryNextServer(reason)
        }
    }

    private fun tryNextServer(message: String) {
        stopProgressCheck()
        if (tryPlaybackRoute()) return
        autoFallbackTried.add(selectedServerIndex)
        renderServerRail()
        for (i in 0 until sources.length()) {
            if (!autoFallbackTried.contains(i)) {
                val from = selectedServerIndex
                emitPlaybackEvent(
                    "playback auto fallback",
                    mapOf(
                        "from_index" to from,
                        "to_index" to i
                    )
                )
                showStatus("$message • trying backup…")
                val generation = playbackGeneration
                val fallback = object : Runnable {
                    override fun run() {
                        if (generation != playbackGeneration || isFinishing || isDestroyed) return
                        if (!activityResumed || player?.playWhenReady == false) {
                            playerView.postDelayed(this, 1000L)
                            return
                        }
                        pendingFallback = null
                        playServer(i)
                    }
                }
                pendingFallback?.let { playerView.removeCallbacks(it) }
                pendingFallback = fallback
                playerView.postDelayed(fallback, 550)
                return
            }
        }
        showStatus("No working server\nTap Server to choose again")
        autoFallbackTried.clear()
        renderServerRail()
    }

    private fun visibleServerIndices(): List<Int> =
        (0 until sources.length()).filter { index ->
            sources.optJSONObject(index)?.optString("transport") !in setOf("vercel-fallback", "cloudflare-fallback")
        }

    private fun displayServerIndex(): Int {
        val source = sources.optJSONObject(selectedServerIndex) ?: return selectedServerIndex
        if (source.optString("transport") !in setOf("vercel-fallback", "cloudflare-fallback")) return selectedServerIndex
        val originalId = source.optString("id").removeSuffix("-vpn-free").removeSuffix("-cloudflare-alt")
        return visibleServerIndices().firstOrNull {
            sources.optJSONObject(it)?.optString("id") == originalId
        } ?: selectedServerIndex
    }

    private fun showServerMenu() {
        clearControlsHideTimer()
        val indices = visibleServerIndices()
        val labels = indices.map { i ->
            serverLabel(i) + "\n" + listOf(safeLineResolution(i), safeLineFormat(i))
                .filter { it.isNotEmpty() }.joinToString(" · ")
        }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Choose line")
            .setSingleChoiceItems(labels, indices.indexOf(displayServerIndex())) { dialog, position ->
                selectServer(indices[position])
                dialog.dismiss()
                setControlsVisible(true)
            }
            .setNegativeButton("Close") { _, _ -> setControlsVisible(true) }
            .setOnDismissListener { setControlsVisible(true) }
            .show()
    }

    private fun selectServer(index: Int) {
        if (index !in 0 until sources.length() || index == selectedServerIndex) return
        autoFallbackTried.clear()
        MainActivity.emitPlayerEvent(
            "playback line selected",
            mapOf(
                "selected_index" to index,
                "line_count" to sources.length()
            )
        )
        playServer(index)
    }

    private fun serverLabel(index: Int): String {
        val source = sources.optJSONObject(index)
        val raw = source?.optString("label")
            ?.trim()
            .orEmpty()
            .ifEmpty { source?.optString("resolution")?.trim().orEmpty() }
        val name = raw.replaceFirst(
            Regex("""(?i)^[^•·\n]{1,90}\s+(?:vs\.?|v)\s+[^•·\n]{1,90}\s*[•·]\s*(.+)$"""),
            "$1"
        ).trim()
        val unsafe = name.length > 80 ||
            Regex("[/?:=&@\\\\]").containsMatchIn(name) ||
            Regex("(?i)\\b(?:referer|origin|authorization|token|key|kid)\\s*[:=]")
                .containsMatchIn(name) ||
            Regex("(?i)\\b[0-9a-f]{24,}\\b").containsMatchIn(name)
        return if (name.isEmpty() || unsafe) "Line ${index + 1}"
            else name.replaceFirst(Regex("""(?i)^\s*([^·•|]+?)\s*[·•|]\s*\1(?=\s*[·•|]|$)"""), "$1").trim()
    }

    private fun safeLineResolution(index: Int): String {
        val raw = sources.optJSONObject(index)?.optString("resolution").orEmpty().trim()
        return if (raw.matches(Regex("(?i)^(?:[0-9]{3,4}p|auto|sd|hd|fhd|uhd|4k)$"))) raw else ""
    }

    private fun safeLineFormat(index: Int): String {
        val source = sources.optJSONObject(index) ?: return ""
        val declared = source.optString("streamType")
            .ifBlank { source.optString("stream_type") }.lowercase(Locale.ROOT)
        return when (declared) {
            "hls", "m3u8" -> "HLS"
            "dash", "mpd" -> "DASH"
            "flv" -> "FLV"
            "mp4" -> "MP4"
            else -> {
                // Fallback only when the source did not declare a type.
                // Never put a raw URL, query token, or secret in the UI.
                val url = source.optString("url").lowercase(Locale.ROOT)
                when {
                    ".m3u8" in url -> "HLS"
                    ".mpd" in url -> "DASH"
                    ".flv" in url -> "FLV"
                    ".mp4" in url -> "MP4"
                    else -> ""
                }
            }
        }
    }

    private fun renderServerRail() {
        if (!::serverRail.isInitialized || !::serverRailScroll.isInitialized) return
        serverRail.removeAllViews()
        // Only the current line stays over the picture; full names are in the chooser.
        val shownIndex = displayServerIndex()
        val current = TextView(this).apply {
            text = "✓ ${serverLabel(shownIndex)} · ${safeLineFormat(shownIndex)}   ▾ Change line"
            textSize = 11f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), 0, dp(10), 0)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
            maxWidth = resources.displayMetrics.widthPixels - dp(16)
            contentDescription = "Current line ${serverLabel(selectedServerIndex)}. Change line"
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(Color.argb(235, 29, 25, 24))
                setStroke(dp(1), Color.rgb(232, 117, 88))
            }
            setOnClickListener { showServerMenu() }
        }
        serverRail.addView(current, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dp(40)
        ))
        renderTheatre()
    }

    // ---------------- Match Theatre (portrait companion panel) ----------------

    private fun buildTheatrePanel(root: FrameLayout) {
        theatreBody = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(20, 18, 18))
            setPadding(dp(18), dp(16), dp(18), dp(28))
        }
        theatrePanel = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            addView(theatreBody)
            visibility = View.GONE
        }
        root.addView(
            theatrePanel,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.TOP
            )
        )
    }

    private fun theatreLabel(text: String): TextView {
        val label = TextView(this)
        label.text = text
        label.textSize = 9.5f
        label.letterSpacing = 0.16f
        label.setTextColor(Color.rgb(232, 130, 103))
        label.setPadding(0, 0, 0, dp(8))
        return label
    }

    private fun suggestedChannels(): List<org.json.JSONObject> {
        val raw = intent.getStringExtra("suggestedChannels").orEmpty()
        if (raw.isBlank()) return emptyList()
        return try {
            val array = org.json.JSONArray(raw)
            (0 until array.length()).mapNotNull { array.optJSONObject(it) }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun featuredPick(): org.json.JSONObject? {
        val raw = intent.getStringExtra("featuredPick").orEmpty()
        if (raw.isBlank()) return null
        return try {
            org.json.JSONObject(raw)
        } catch (_: Throwable) {
            null
        }
    }

    private fun isNightMode(): Boolean =
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private fun cardBackground(radiusDp: Int): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dp(radiusDp).toFloat()
        if (isNightMode()) {
            setColor(Color.rgb(28, 25, 24))
            setStroke(dp(1), Color.argb(20, 255, 255, 255))
        } else {
            setColor(Color.rgb(250, 247, 245))
            setStroke(dp(1), Color.argb(255, 255, 255, 255))
        }
    }

    private fun primaryInk(): Int =
        if (isNightMode()) Color.rgb(250, 247, 245) else Color.rgb(29, 25, 24)

    private fun secondaryInk(): Int =
        if (isNightMode()) Color.rgb(163, 155, 151) else Color.rgb(115, 106, 102)

    private fun coralPill(text: String): TextView = TextView(this).apply {
        this.text = text
        textSize = 12f
        typeface = Typeface.create("sans-serif", Typeface.BOLD)
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
        setPadding(dp(18), dp(12), dp(18), dp(12))
        background = GradientDrawable(
            GradientDrawable.Orientation.LEFT_RIGHT,
            intArrayOf(Color.rgb(244, 151, 126), Color.rgb(232, 130, 103))
        ).apply { cornerRadius = dp(999).toFloat() }
    }

    private fun circleAction(label: String, description: String): TextView = TextView(this).apply {
        text = label
        contentDescription = description
        textSize = 15f
        setTextColor(primaryInk())
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            if (isNightMode()) {
                setColor(Color.rgb(35, 32, 32))
                setStroke(dp(1), Color.argb(40, 255, 255, 255))
            } else {
                setColor(Color.rgb(255, 255, 255))
                setStroke(dp(1), Color.argb(28, 29, 25, 24))
            }
        }
    }

    /** Portrait feed: header, actions, AI tip, and suggested channels. */
    private fun renderTheatre() {
        if (!::theatreBody.isInitialized) return
        theatreBody.removeAllViews()
        theatreBody.setBackgroundColor(
            if (isNightMode()) Color.rgb(18, 16, 16) else Color.rgb(250, 247, 245)
        )
        theatreBody.setPadding(dp(16), dp(14), dp(16), dp(112))

        val title = intent.getStringExtra("title").orEmpty().ifBlank { "Live stream" }
        val parts = title.split("•", "·").map { it.trim() }.filter { it.isNotEmpty() }
        val channelName = parts.firstOrNull() ?: title
        val matchName = if (parts.size > 1) parts.drop(1).joinToString(" · ") else ""

        // ---- header row ----
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val avatar = TextView(this).apply {
            text = channelName.trim().take(1).uppercase(Locale.ROOT)
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.rgb(232, 130, 103))
                setStroke(dp(2), Color.argb(160, 255, 255, 255))
            }
        }
        header.addView(avatar, LinearLayout.LayoutParams(dp(40), dp(40)))
        val titles = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, 0, 0)
        }
        titles.addView(TextView(this).apply {
            text = channelName
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(primaryInk())
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        titles.addView(TextView(this).apply {
            text = if (matchName.isNotBlank()) matchName else "Now on " + serverLabel(displayServerIndex())
            textSize = 11.5f
            setTextColor(secondaryInk())
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        header.addView(titles, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(TextView(this).apply {
            text = "● LIVE"
            textSize = 9.5f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.rgb(232, 130, 103))
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = GradientDrawable().apply {
                cornerRadius = dp(999).toFloat()
                setColor(Color.argb(36, 232, 130, 103))
                setStroke(dp(1), Color.argb(90, 232, 130, 103))
            }
        })
        theatreBody.addView(header, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(2) })

        // ---- action row: switch line + audio + settings ----
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val lineCount = visibleServerIndices().size
        val switchPill = coralPill(
            if (lineCount > 1) "Switch line · $lineCount lines"
            else "Line: " + serverLabel(displayServerIndex())
        ).apply {
            setOnClickListener { if (lineCount > 1) showServerMenu() }
        }
        actions.addView(switchPill, LinearLayout.LayoutParams(
            0, dp(46), 1f
        ))
        val audioButton = circleAction("\u266A", "Audio only mode").apply {
            if (audioOnlyMode) {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.rgb(232, 130, 103))
                }
            }
            setOnClickListener { setAudioOnly(!audioOnlyMode); renderTheatre() }
        }
        actions.addView(audioButton, LinearLayout.LayoutParams(dp(46), dp(46)).apply {
            leftMargin = dp(10)
        })
        val settingsButton = circleAction("\u22EE", "Video settings").apply {
            setOnClickListener {
                if (::settingsPanel.isInitialized) openSettingsMenu("video")
            }
        }
        actions.addView(settingsButton, LinearLayout.LayoutParams(dp(46), dp(46)).apply {
            leftMargin = dp(10)
        })
        theatreBody.addView(actions, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(16) })

        // ---- AI tip card ----
        val pick = featuredPick()
        if (pick != null) {
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(14), dp(12), dp(14), dp(12))
                background = cardBackground(18)
            }
            card.addView(TextView(this).apply {
                text = "NOELLYNE AI PICK"
                textSize = 9.5f
                letterSpacing = 0.16f
                setTextColor(Color.rgb(232, 130, 103))
            })
            card.addView(TextView(this).apply {
                text = pick.optString("match").ifBlank { "Today's pick" }
                textSize = 13f
                setTypeface(typeface, Typeface.BOLD)
                setTextColor(primaryInk())
                setPadding(0, dp(6), 0, 0)
                maxLines = 2
            })
            val pickLine = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(4), 0, 0)
            }
            pickLine.addView(TextView(this).apply {
                text = pick.optString("pick")
                textSize = 12f
                setTextColor(secondaryInk())
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            val odds = pick.optString("odds")
            if (odds.isNotBlank()) {
                pickLine.addView(TextView(this).apply {
                    text = odds
                    textSize = 13f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(primaryInk())
                    setPadding(dp(10), 0, 0, 0)
                })
            }
            card.addView(pickLine)
            val copyText = pick.optString("copyText").ifBlank {
                pick.optString("match") + " — " + pick.optString("pick") + " " + odds
            }
            card.addView(TextView(this).apply {
                text = "Copy"
                textSize = 11f
                setTypeface(typeface, Typeface.BOLD)
                setTextColor(Color.rgb(232, 130, 103))
                setPadding(0, dp(8), 0, 0)
                setOnClickListener {
                    try {
                        val clipboard = this@NativePlayerActivity
                            .getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        clipboard.setPrimaryClip(
                            android.content.ClipData.newPlainText("Noellyne pick", copyText)
                        )
                        android.widget.Toast.makeText(
                            this@NativePlayerActivity, "Copied to clipboard",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    } catch (_: Throwable) {
                    }
                }
            })
            theatreBody.addView(card, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(14) })
        }

        // ---- suggested channels ----
        val suggested = suggestedChannels()
        if (suggested.isNotEmpty()) {
            theatreBody.addView(TextView(this).apply {
                text = "UP NEXT & SUGGESTED"
                textSize = 9.5f
                letterSpacing = 0.18f
                setTextColor(secondaryInk())
                setPadding(0, dp(20), 0, dp(10))
            })
            for (item in suggested.take(12)) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(8), dp(8), dp(8), dp(8))
                    background = cardBackground(16)
                }
                val stage = TextView(this).apply {
                    text = item.optString("name").trim().take(1).uppercase(Locale.ROOT)
                    textSize = 18f
                    gravity = Gravity.CENTER
                    setTextColor(Color.rgb(29, 25, 24))
                    background = GradientDrawable().apply {
                        cornerRadius = dp(14).toFloat()
                        setColor(Color.rgb(244, 151, 126))
                    }
                }
                row.addView(stage, LinearLayout.LayoutParams(dp(108), dp(62)))
                val column = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(12), 0, 0, 0)
                }
                column.addView(TextView(this).apply {
                    text = item.optString("name").ifBlank { "Channel" }
                    textSize = 13f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(primaryInk())
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                })
                column.addView(TextView(this).apply {
                    text = item.optString("subtitle").ifBlank { "Live match" }
                    textSize = 11f
                    setTextColor(secondaryInk())
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, dp(3), 0, 0)
                })
                row.addView(column, LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
                ))
                val id = item.optString("id")
                row.setOnClickListener {
                    if (id.isNotBlank()) {
                        MainActivity.emitPlayerEvent("openMatch", mapOf("matchId" to id))
                        finish()
                    }
                }
                theatreBody.addView(row, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(10) })
            }
        } else {
            theatreBody.addView(TextView(this).apply {
                text = "Switch line or rotate for full screen. Suggested channels appear " +
                    "here once the feed hands them over."
                textSize = 11f
                setTextColor(secondaryInk())
                setPadding(0, dp(18), 0, 0)
            })
        }
    }

    /** Floating stadium dock for portrait; hidden in landscape / PiP. */
    private fun buildDock(root: FrameLayout) {
        playerDock = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = GradientDrawable().apply {
                cornerRadius = dp(999).toFloat()
                if (isNightMode()) {
                    setColor(Color.argb(228, 28, 25, 24))
                    setStroke(dp(1), Color.argb(30, 255, 255, 255))
                } else {
                    setColor(Color.argb(236, 255, 255, 255))
                    setStroke(dp(1), Color.argb(40, 29, 25, 24))
                }
            }
            visibility = View.GONE
        }
        val tabs = listOf("Live", "Matches", "Channels", "More")
        val activeIndex = intent.getIntExtra("activeTabIndex", 0)
        for (index in tabs.indices) {
            val tab = TextView(this).apply {
                text = tabs[index]
                textSize = 10.5f
                gravity = Gravity.CENTER
                setTypeface(typeface, if (index == activeIndex) Typeface.BOLD else Typeface.NORMAL)
                setTextColor(
                    if (index == activeIndex) Color.rgb(232, 130, 103) else secondaryInk()
                )
                setPadding(0, dp(10), 0, dp(10))
            }
            tab.setOnClickListener {
                MainActivity.emitPlayerEvent("navigateToTab", mapOf("index" to index))
                finish()
            }
            playerDock.addView(tab, LinearLayout.LayoutParams(0, dp(44), 1f))
        }
        val ai = TextView(this).apply {
            text = "\u2726"
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(244, 151, 126), Color.rgb(232, 130, 103))
            ).apply { shape = GradientDrawable.OVAL }
            setOnClickListener {
                MainActivity.emitPlayerEvent("navigateToTab", mapOf("index" to 4))
                finish()
            }
        }
        playerDock.addView(ai, LinearLayout.LayoutParams(dp(48), dp(48)).apply {
            leftMargin = dp(8)
        })
        root.addView(playerDock, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ).apply {
            leftMargin = dp(12)
            rightMargin = dp(12)
            bottomMargin = dp(14)
        })
    }

    private fun rebuildQualityOptions(tracks: Tracks) {
        val best = linkedMapOf<String, QualityOption>()
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                val height = format.height
                if (height <= 0) continue
                val bitrate = format.bitrate
                val width = format.width.coerceAtLeast(0)
                val label = if (bitrate > 0)
                    "${width} × ${height} • ${String.format(Locale.US, "%.2f", bitrate / 1000000.0)} Mbps"
                    else "${height}p"
                val option = QualityOption(label, group, trackIndex, height, bitrate)
                best["${width}x${height}@${bitrate}"] = option
            }
        }
        qualityOptions = best.values.sortedWith(
            compareByDescending<QualityOption> { it.height }.thenByDescending { it.bitrate }
        ).toMutableList()
        runOnUiThread {
            qualityButton.text = forcedQualityLabel ?: "Auto"
            qualityButton.visibility = View.VISIBLE
        }
    }

    // Web reference: dark, compact, tabbed PLAYER SETTINGS dialog with a
    // real close X, compact system-font rows and selected green checkmarks.
    // Only the controls are native views; Media3 and its track selector stay intact.
    private fun buildSettingsPanel(root: FrameLayout) {
        settingsPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            elevation = dp(14).toFloat()
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.rgb(20, 18, 18))
                setStroke(dp(1), Color.rgb(71, 72, 83))
            }
            clipToPadding = false
            contentDescription = "Player settings"
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(9), dp(7), dp(9), dp(4))
        }
        val back = overlayButton("←").apply {
            textSize = 16f
            contentDescription = "Back to video settings"
            setOnClickListener {
                if (settingsSection == "video") closeSettingsMenu()
                else openSettingsMenu("video")
            }
        }
        val heading = TextView(this).apply {
            text = "PLAYER SETTINGS"
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            letterSpacing = 0.02f
            setTextColor(Color.rgb(168, 156, 150))
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), 0, dp(6), 0)
        }
        val close = overlayButton("✕").apply {
            textSize = 16f
            contentDescription = "Close player settings"
            setOnClickListener { closeSettingsMenu() }
        }
        header.addView(back, LinearLayout.LayoutParams(dp(34), dp(34)))
        header.addView(heading, LinearLayout.LayoutParams(0, dp(34), 1f))
        header.addView(close, LinearLayout.LayoutParams(dp(34), dp(34)))
        settingsPanel.addView(header, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(45)))

        settingsItems = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(7), dp(3), dp(7), dp(7))
        }
        settingsScroll = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            isFillViewport = false
            addView(settingsItems, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        settingsPanel.addView(settingsScroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(settingsPanel, FrameLayout.LayoutParams(
            dp(335), ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END
        ).apply {
            topMargin = dp(54)
            rightMargin = dp(8) + displayCutoutSafeRight
        })
    }

    private fun positionSettingsPanel(root: FrameLayout, landscape: Boolean) {
        if (!::settingsPanel.isInitialized) return
        val widthAvailable = (root.width - dp(16) - displayCutoutSafeRight)
            .coerceAtLeast(dp(160))
        val width = if (landscape) {
            minOf(dp(335), widthAvailable, (root.width * 0.48f).toInt().coerceAtLeast(dp(180)))
        } else minOf(dp(335), widthAvailable)
        settingsPanel.layoutParams = (settingsPanel.layoutParams as FrameLayout.LayoutParams).apply {
            this.width = width
            this.height = ViewGroup.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.END
            topMargin = if (landscape) dp(50) else dp(54)
            rightMargin = dp(8)
        }
    }

    private fun settingsBackground(selected: Boolean, radius: Int = 8): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = dp(radius).toFloat()
            setColor(if (selected) Color.rgb(58, 30, 24) else Color.rgb(29, 29, 29))
            setStroke(dp(1), if (selected) Color.rgb(229, 117, 88)
                else Color.rgb(65, 65, 65))
        }

    private fun addSettingsChoice(
        label: String,
        subtitle: String,
        selected: Boolean,
        enabled: Boolean = true,
        onSelect: () -> Unit
    ) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(36)
            setPadding(dp(8), dp(5), dp(8), dp(5))
            background = settingsBackground(selected)
            alpha = if (enabled) 1f else 0.48f
            isClickable = enabled
            isFocusable = enabled
            contentDescription = label + if (selected) ", selected" else ""
            if (enabled) setOnClickListener {
                onSelect()
                closeSettingsMenu()
                updateCompactControls()
            }
        }
        val textColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
        }
        textColumn.addView(TextView(this).apply {
            text = label
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setTextColor(Color.WHITE)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        textColumn.addView(TextView(this).apply {
            text = subtitle
            textSize = 10f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            setTextColor(Color.rgb(168, 156, 150))
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        row.addView(textColumn, LinearLayout.LayoutParams(0,
            ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (selected) row.addView(TextView(this).apply {
            text = "✓"
            textSize = 11f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setTextColor(Color.rgb(244, 170, 150))
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(dp(26), dp(24)))
        settingsItems.addView(row, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = dp(3)
            bottomMargin = dp(3)
        })
    }

    private fun showPlaybackSettings() {
        if (!::settingsPanel.isInitialized) return
        if (settingsPanel.visibility == View.VISIBLE) closeSettingsMenu()
        else openSettingsMenu("video")
    }

    private fun closeSettingsMenu() {
        if (::settingsPanel.isInitialized) settingsPanel.visibility = View.GONE
        setControlsVisible(true)
    }

    private fun openSettingsMenu(section: String) {
        if (!::settingsPanel.isInitialized || isFinishing || isDestroyed) return
        settingsSection = section
        settingsItems.removeAllViews()
        val tabs = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(3), 0, dp(5))
        }
        for ((key, label) in listOf(
            "video" to "VIDEO", "audio" to "AUDIO",
            "subtitles" to "SUBTITLES", "speed" to "SPEED"
        )) {
            val active = section == key
            val tab = overlayButton(label).apply {
                textSize = 10f
                background = settingsBackground(active, 7)
                setTextColor(if (active) Color.rgb(244, 170, 150) else Color.WHITE)
                setPadding(dp(2), 0, dp(2), 0)
                contentDescription = label + if (active) ", selected tab" else " tab"
                setOnClickListener { openSettingsMenu(key) }
            }
            tabs.addView(tab, LinearLayout.LayoutParams(0, dp(34), 1f).apply {
                marginEnd = if (key != "speed") dp(3) else 0
            })
        }
        settingsItems.addView(tabs, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))
        var choices = 0
        fun choice(label: String, subtitle: String, selected: Boolean,
            enabled: Boolean = true, select: () -> Unit) {
            addSettingsChoice(label, subtitle, selected, enabled, select)
            choices++
        }

        when (section) {
            "video" -> {
                val selector = trackSelector
                val generation = playbackGeneration
                choice("Auto", "Adaptive quality", forcedQualityLabel == null) {
                    if (generation != playbackGeneration || selector == null) return@choice
                    selector.parameters = selector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_VIDEO).build()
                    forcedQualityLabel = null
                    qualityButton.text = "Auto"
                    emitPlaybackEvent("playback quality selected", mapOf("quality" to "auto"))
                }
                qualityOptions.forEach { option ->
                    choice(option.label, "Video track", forcedQualityLabel == option.label) {
                        if (generation != playbackGeneration || selector == null) return@choice
                        val override = TrackSelectionOverride(option.group.mediaTrackGroup, option.trackIndex)
                        selector.parameters = selector.buildUponParameters()
                            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                            .setOverrideForType(override).build()
                        forcedQualityLabel = option.label
                        qualityButton.text = option.label
                        emitPlaybackEvent("playback quality selected",
                            mapOf("quality" to option.label))
                    }
                }
                if (qualityOptions.isEmpty()) {
                    choice("Auto only", "No manual video track exposed by stream.", false, false) {}
                }
            }
            "audio" -> {
                val selector = trackSelector
                choice("Auto", "Default audio", selectedAudioLabel == null) {
                    if (selector == null) return@choice
                    selector.parameters = selector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_AUDIO).build()
                    selectedAudioLabel = null
                }
                player?.currentTracks?.groups?.forEach { group ->
                    if (group.type != C.TRACK_TYPE_AUDIO) return@forEach
                    for (i in 0 until group.length) {
                        if (!group.isTrackSupported(i)) continue
                        val format = group.getTrackFormat(i)
                        val language = format.language?.takeIf { it.isNotBlank() } ?: "Track"
                        val label = listOfNotNull(
                            format.label?.takeIf { it.isNotBlank() }, language
                        ).distinct().joinToString(" • ")
                        choice(label, "Audio track", selectedAudioLabel == label) {
                            if (selector == null) return@choice
                            selector.parameters = selector.buildUponParameters()
                                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                                .build()
                            selectedAudioLabel = label
                        }
                    }
                }
            }
            "subtitles" -> {
                val selector = trackSelector
                choice("Off", "Disable subtitles", selectedSubtitleLabel == null) {
                    if (selector == null) return@choice
                    selector.parameters = selector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
                    selectedSubtitleLabel = null
                }
                player?.currentTracks?.groups?.forEach { group ->
                    if (group.type != C.TRACK_TYPE_TEXT) return@forEach
                    for (i in 0 until group.length) {
                        if (!group.isTrackSupported(i)) continue
                        val format = group.getTrackFormat(i)
                        val label = format.label?.takeIf { it.isNotBlank() }
                            ?: format.language?.takeIf { it.isNotBlank() }
                            ?: "Subtitles " + (i + 1)
                        choice(label, "Subtitle track", selectedSubtitleLabel == label) {
                            if (selector == null) return@choice
                            selector.parameters = selector.buildUponParameters()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                                .build()
                            selectedSubtitleLabel = label
                        }
                    }
                }
            }
            else -> {
                val exo = player
                for (speed in listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)) {
                    val label = if (speed == 1f) "Normal · 1×" else speed.toString() + "×"
                    choice(label, "Playback speed",
                        exo != null && kotlin.math.abs(exo.playbackParameters.speed - speed) < 0.01f) {
                        exo?.setPlaybackSpeed(speed)
                    }
                }
            }
        }
        settingsPanel.visibility = View.VISIBLE
        setControlsVisible(true)
        // Up to 455dp like Web. Short option lists do not create a blank box.
        val root = settingsPanel.parent as? FrameLayout
        val heightAvailable = root?.height?.takeIf { it > 0 }
            ?: resources.displayMetrics.heightPixels
        val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        if (root != null && root.width > 0) positionSettingsPanel(root, isLandscape)
        val maxScroll = minOf(dp(455), (heightAvailable * 0.61f).toInt()
            .coerceAtLeast(dp(90)))
        settingsScroll.layoutParams = (settingsScroll.layoutParams as LinearLayout.LayoutParams).apply {
            height = minOf(maxScroll, dp(42) + choices * dp(49))
        }
        settingsScroll.scrollTo(0, 0)
        compactControls.visibility = View.VISIBLE
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onBackPressed() {
        if (::settingsPanel.isInitialized && settingsPanel.visibility == View.VISIBLE) {
            closeSettingsMenu()
        } else {
            super.onBackPressed()
        }
    }

    private fun toggleDisplayMode() {
        if (!::playerView.isInitialized || !::displayModeButton.isInitialized) return
        displayMode = (displayMode + 1) % 3
        applyDisplayMode()
    }

    private fun applyDisplayMode() {
        if (!::playerView.isInitialized) return
        // Do not crop the score overlay by default; the video host remains a
        // 16:9 frame in portrait, and fullscreen in landscape.
        playerView.resizeMode = when (displayMode) {
            0 -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            1 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        }
        if (::displayModeButton.isInitialized) {
            displayModeButton.text = when (displayMode) {
                0 -> "Fit"
                1 -> "Full"
                else -> "Zoom"
            }
            displayModeButton.contentDescription = when (displayMode) {
                0 -> "Fit video; tap for Full"
                1 -> "Stretch to fill; tap for Zoom"
                else -> "Crop to fill; tap for Fit"
            }
        }
    }

    private fun showStatus(text: String) {
        runOnUiThread {
            if (::playerLoader.isInitialized) playerLoader.show(text)
        }
    }

    private fun hideStatus() {
        runOnUiThread {
            if (::playerLoader.isInitialized) playerLoader.hide()
        }
    }

    private fun showFatalError(text: String) {
        sourceSessions.close(sessionId)
        if (activePlayer.get() === this) activePlayer.clear()
        MainActivity.emitPlayerEvent(
            "playback fatal error",
            mapOf("reason" to text.lineSequence().firstOrNull().orEmpty().take(80))
        )
        val root = FrameLayout(this).apply { setBackgroundColor(Color.rgb(20, 18, 18)) }
        val message = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            this.text = "$text\n\nTap to go back"
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setOnClickListener { finish() }
        }
        root.addView(message, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)
    }

    private fun overlayButton(value: String): TextView {
        return TextView(this).apply {
            text = value
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            // Frosted circular chrome, matching the Flutter design system.
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(132, 0, 0, 0))
                setStroke(dp(1), Color.argb(36, 255, 255, 255))
            }
            isClickable = true
            isFocusable = true
        }
    }

    private fun statusBarHeightPx(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else dp(24)
    }

    private fun isLandscapeNow(): Boolean =
        resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    private fun safeHideSystemBars() {
        // Portrait behaves like YouTube: the status bar stays visible and the
        // picture starts underneath it. Only full-screen landscape goes
        // immersive.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
                window.insetsController?.let { c ->
                    if (isLandscapeNow()) {
                        c.hide(
                            WindowInsets.Type.statusBars() or
                                WindowInsets.Type.navigationBars()
                        )
                        c.systemBarsBehavior =
                            WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    } else {
                        c.show(WindowInsets.Type.statusBars())
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = if (isLandscapeNow())
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                else
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        } catch (_: Throwable) {
            // Fullscreen behavior is optional; playback should still continue.
        }
    }

    override fun onDestroy() {
        // Audio mode: the foreground service keeps the stream audible after the
        // player screen is dismissed, so the player is handed to the bridge
        // instead of being released.
        val keepPlaying = audioOnlyMode && player != null
        if (keepPlaying) {
            PlaybackAudioBridge.player = player
        } else {
            PlaybackAudioService.stop(this)
            PlaybackAudioBridge.player = null
        }
        clearControlsHideTimer()
        sourceSessions.close(sessionId)
        if (activePlayer.get() === this) activePlayer.clear()
        stopProgressCheck()
        pendingFallback?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        pendingFallback = null
        playbackGeneration += 1
        if (::playerView.isInitialized) playerView.player = null
        if (!keepPlaying) player?.release()
        player = null
        trackSelector = null
        super.onDestroy()
    }

    override fun onPause() {
        clearControlsHideTimer()
        activityResumed = false
        updatePlaybackTiming(false)
        stopProgressCheck()
        pendingFallback?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        player?.let { progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), it.currentPosition) }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        if (::playerView.isInitialized && controlsVisible) setControlsVisible(true)
        val exo = player ?: return
        updatePlaybackTiming(exo.playWhenReady)
        progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), exo.currentPosition)
        val fallback = pendingFallback
        if (fallback != null) {
            playerView.removeCallbacks(fallback)
            playerView.postDelayed(fallback, 550L)
        } else if (exo.playbackState == Player.STATE_ENDED) {
            if (exo.playWhenReady && exo.isCurrentMediaItemLive) recoverOrFallback("Live stream ended")
        } else {
            startProgressCheck(exo, playbackGeneration)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun toBase64Url(value: String): String {
        val clean = value.replace(" ", "").trim()
        if (clean.matches(Regex("^[0-9a-fA-F]+$")) && clean.length % 2 == 0) {
            val bytes = ByteArray(clean.length / 2)
            for (i in bytes.indices) {
                val p = i * 2
                bytes[i] = clean.substring(p, p + 2).toInt(16).toByte()
            }
            return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        }
        return clean.replace("+", "-").replace("/", "_").trimEnd('=')
    }
}
