package com.example.football_viewer

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val channelName = "football_stream/native_player"
    private val authLinkChannelName = "noellyne/auth_links"
    private var authLinkChannel: MethodChannel? = null
    private var pendingAuthLink: String? = null

    companion object {
        const val PLAYER_REQUEST = 4711
        private var playerEventChannel: MethodChannel? = null

        fun emitPlayerEvent(
            event: String,
            properties: Map<String, Any?> = emptyMap()
        ) {
            playerEventChannel?.invokeMethod(
                "playerEvent",
                mapOf(
                    "event" to event,
                    "properties" to properties
                )
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        captureAuthUri(intent)

        val linkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            authLinkChannelName
        )
        authLinkChannel = linkChannel
        linkChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialAuthLink" -> {
                    val link = pendingAuthLink
                    pendingAuthLink = null
                    result.success(link)
                }
                "getDeviceFingerprint" -> {
                    result.success(computeHardwareFingerprint())
                }
                else -> result.notImplemented()
            }
        }

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        playerEventChannel = channel

        channel.setMethodCallHandler { call, result ->
            if (call.method == "updatePlayerSources") {
                val sessionId = call.argument<String>("sessionId").orEmpty()
                val sourcesJson = call.argument<String>("sourcesJson").orEmpty()
                result.success(NativePlayerActivity.appendSources(sessionId, sourcesJson))
                return@setMethodCallHandler
            }
            if (call.method != "openPlayer") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcesJson = call.argument<String>("sourcesJson").orEmpty()
            if (sourcesJson.isBlank()) {
                result.error("EMPTY_SOURCES", "No player sources.", null)
                return@setMethodCallHandler
            }

            val sessionId = call.argument<String>("sessionId").orEmpty()
            NativePlayerActivity.prepareOpeningSession(sessionId)
            val playerIntent = Intent(this, NativePlayerActivity::class.java).apply {
                putExtra("sourcesJson", sourcesJson)
                putExtra("selectedIndex", call.argument<Int>("selectedIndex") ?: 0)
                putExtra("title", call.argument<String>("title").orEmpty())
                putExtra("matchId", call.argument<String>("matchId").orEmpty())
                putExtra("sessionId", sessionId)
                putExtra(
                    "suggestedChannels",
                    call.argument<String>("suggestedChannels").orEmpty()
                )
                putExtra("featuredPick", call.argument<String>("featuredPick").orEmpty())
                putExtra("activeTabIndex", call.argument<Int>("activeTabIndex") ?: 0)
                // The player follows the in-app theme, never the system one.
                putExtra("isDark", call.argument<Boolean>("isDark") ?: false)
            }
            try {
                // Result comes back with `navigateToTab` so real tabs open.
                startActivityForResult(playerIntent, PLAYER_REQUEST)
            } catch (_: Exception) {
                NativePlayerActivity.cancelOpeningSession(sessionId)
                result.error("PLAYER_OPEN_FAILED", "Could not open player.", null)
                return@setMethodCallHandler
            }

            result.success(null)
        }
    }

    /**
     * Produces a privacy-safe, one-way SHA-256 hardware fingerprint derived from
     * `Settings.Secure.ANDROID_ID` + device hardware model. Survives Clear Cache,
     * Clear App Data, and Uninstall/Reinstall without requiring any permissions.
     */
    private fun computeHardwareFingerprint(): String {
        return try {
            val androidId = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ANDROID_ID
            ).orEmpty().trim()
            val raw = "nly-hw-v1|$androidId|${Build.BRAND}|${Build.MANUFACTURER}|${Build.MODEL}"
            val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
            val hex = digest.joinToString("") { "%02x".format(it) }
            "hw-${hex.take(24)}"
        } catch (_: Exception) {
            ""
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = extractAuthUri(intent) ?: return
        if (authLinkChannel != null) {
            authLinkChannel?.invokeMethod("onAuthCallback", uri)
        } else {
            pendingAuthLink = uri
        }
    }

    private fun extractAuthUri(intent: Intent?): String? {
        val data = intent?.data ?: return null
        return if (data.scheme == "noellyne") data.toString() else null
    }

    private fun captureAuthUri(intent: Intent?) {
        val uri = extractAuthUri(intent)
        if (uri != null) pendingAuthLink = uri
    }

    /**
     * The native player hands tab taps back here (`navigateToTab`), so the real
     * Flutter tab opens instead of dropping the user on the previous screen.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PLAYER_REQUEST) return
        val tab = data?.getIntExtra("navigateToTab", -1) ?: -1
        if (resultCode == Activity.RESULT_OK && tab >= 0) {
            emitPlayerEvent("navigateToTab", mapOf("index" to tab))
        }
    }
}
