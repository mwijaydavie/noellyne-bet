package com.example.football_viewer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.media3.common.Player

/**
 * Shared handle to the ExoPlayer that lives inside NativePlayerActivity, so the
 * foreground service can drive playback from the notification (and keep the
 * audio alive when the activity is not on screen).
 */
object PlaybackAudioBridge {
    @Volatile
    var player: Player? = null

    @Volatile
    var title: String = "Noellyne Bet"

    @Volatile
    var subtitle: String = "Live stream"

    fun togglePlayPause() {
        val current = player ?: return
        if (current.isPlaying) current.pause() else current.play()
    }

    fun pause() {
        player?.pause()
    }
}

/**
 * Media-playback foreground service.
 *
 * Why this exists: Android kills a background ExoPlayer process unless a
 * foreground service with `foregroundServiceType="mediaPlayback"` is running.
 * That service is what makes the headphones mode behave like YouTube's
 * "On-the-go": the audio keeps playing with the screen locked or the app
 * minimised, and the user gets a notification with a play/pause action.
 */
class PlaybackAudioService : Service() {

    companion object {
        private const val CHANNEL_ID = "noellyne_playback"
        private const val NOTIFICATION_ID = 4711
        private const val ACTION_TOGGLE = "com.example.football_viewer.playback.TOGGLE"
        private const val ACTION_STOP = "com.example.football_viewer.playback.STOP"

        fun start(context: Context, title: String, subtitle: String) {
            PlaybackAudioBridge.title = title
            PlaybackAudioBridge.subtitle = subtitle
            try {
                val intent = Intent(context, PlaybackAudioService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Throwable) {
                // A restricted OEM may refuse background starts; playback in
                // the activity still works, it just will not survive the
                // process being reclaimed.
            }
        }

        fun update(title: String, subtitle: String) {
            PlaybackAudioBridge.title = title
            PlaybackAudioBridge.subtitle = subtitle
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, PlaybackAudioService::class.java))
            } catch (_: Throwable) {
            }
        }

        fun refresh(context: Context) {
            try {
                val manager =
                    context.getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, build(context, null))
            } catch (_: Throwable) {
            }
        }

        private fun immutableFlag(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        private fun build(context: Context, action: String?): Notification {
            val manager =
                context.getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Live playback",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps live audio playing in the background"
                    setShowBadge(false)
                }
                manager.createNotificationChannel(channel)
            }

            val openIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val contentIntent = openIntent?.let {
                PendingIntent.getActivity(
                    context, 0, it,
                    PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
                )
            }

            val toggleIntent = PendingIntent.getService(
                context, 1,
                Intent(context, PlaybackAudioService::class.java).setAction(ACTION_TOGGLE),
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
            val stopIntent = PendingIntent.getService(
                context, 2,
                Intent(context, PlaybackAudioService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )

            val playing = PlaybackAudioBridge.player?.isPlaying != false
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            builder
                .setContentTitle(PlaybackAudioBridge.title)
                .setContentText(PlaybackAudioBridge.subtitle)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setOngoing(playing)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
            if (contentIntent != null) builder.setContentIntent(contentIntent)
            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    if (playing) "Pause" else "Play",
                    toggleIntent
                ).build()
            )
            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopIntent
                ).build()
            )
            return builder.build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> {
                PlaybackAudioBridge.togglePlayPause()
                refresh(this)
            }
            ACTION_STOP -> {
                PlaybackAudioBridge.pause()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val notification = build(this, null)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Throwable) {
            // On Android 14+ a missing FOREGROUND_SERVICE_MEDIA_PLAYBACK
            // permission throws; degrade to a plain background service.
        }
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            stopForeground(true)
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }
}
