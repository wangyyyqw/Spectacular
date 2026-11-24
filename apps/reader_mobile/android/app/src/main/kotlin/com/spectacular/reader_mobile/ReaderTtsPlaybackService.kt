package com.spectacular.reader_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/** 保持现有 Flutter 听书会话运行；不在服务内复制文本或播放器。 */
class ReaderTtsPlaybackService : Service() {
    companion object {
        private const val CHANNEL_ID = "reader_tts_playback"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_START = "start"
        private const val ACTION_END = "end_listening"
        var instance: ReaderTtsPlaybackService? = null
            private set
        var channel: MethodChannel? = null
        private var pendingStart: MethodChannel.Result? = null

        fun start(context: Context, title: String, result: MethodChannel.Result) {
            val active = instance
            if (active != null) {
                active.bookTitle = title
                active.activate(result)
                return
            }
            pendingStart = result
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, ReaderTtsPlaybackService::class.java)
                        .setAction(ACTION_START).putExtra("bookTitle", title),
                )
            } catch (error: RuntimeException) {
                pendingStart = null
                result.error("playback_start_failed", "无法启动后台听书：${error.message}", null)
            }
        }
    }

    private lateinit var mediaSession: MediaSession
    private lateinit var audioManager: AudioManager
    private lateinit var notifications: NotificationManager
    private lateinit var wakeLock: PowerManager.WakeLock
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false
    private var phase = "paused"
    private var bookTitle = "听书"
    private var chapterTitle = ""
    private var pendingStop: MethodChannel.Result? = null
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
        ) interruptPlayback()
    }
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) interruptPlayback()
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        audioManager = getSystemService(AudioManager::class.java)
        notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "听书播放", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "后台听书与播放控制" },
            )
        }
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "$packageName:tts_playback",
        ).apply { setReferenceCounted(false) }
        createMediaSession()
        ContextCompat.registerReceiver(
            this, noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    @Suppress("DEPRECATION")
    private fun createMediaSession() {
        mediaSession = MediaSession(this, "墨屿听书")
        mediaSession.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        mediaSession.setPlaybackToLocal(attributes)
        mediaSession.setSessionActivity(openReaderIntent())
        mediaSession.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = sendCommand("play")
            override fun onPause() = sendCommand("pause")
            override fun onStop() = sendCommand("stop")
            override fun onCustomAction(action: String, extras: Bundle?) {
                if (action == ACTION_END) sendCommand("stop")
            }
        })
        mediaSession.isActive = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START) {
            bookTitle = intent.getStringExtra("bookTitle") ?: "听书"
            val result = pendingStart
            pendingStart = null
            activate(result, starting = true)
        } else if (intent?.action in setOf("play", "pause", "stop") && channel != null) {
            sendCommand(intent!!.action!!)
        } else {
            finish()
        }
        // 阅读会话已被用户或系统结束时，不复活一个没有原文游标的服务。
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    fun activate(result: MethodChannel.Result?, starting: Boolean = false) {
        try {
            phase = "loading"
            publish()
            if (!requestFocus()) {
                update("paused", chapterTitle)
                if (starting) finish()
                result?.error("audio_focus_denied", "音频正被其他应用占用，请稍后继续听书", null)
                return
            }
            // 播放与逐段合成期间保持 CPU 运行，暂停和结束立即释放。
            if (!wakeLock.isHeld) wakeLock.acquire()
            result?.success(null)
        } catch (error: RuntimeException) {
            finish()
            result?.error("playback_activate_failed", "后台听书不可用：${error.message}", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        if (hasFocus) return true
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes).setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(focusListener, Handler(Looper.getMainLooper()))
                .build().also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        hasFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasFocus
    }

    @Suppress("DEPRECATION")
    private fun releaseFocus() {
        if (!hasFocus) return
        hasFocus = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    private fun interruptPlayback() {
        if (phase != "paused") sendCommand("pause")
    }

    private fun sendCommand(command: String) {
        if (command == "pause") update("paused", chapterTitle)
        val connection = channel
        if (connection == null) {
            finish()
            return
        }
        connection.invokeMethod(command, null, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) {
                Log.w("ReaderTtsPlayback", "听书操作失败：$code $message")
            }
            override fun notImplemented() {
                finish()
            }
        })
    }

    fun update(nextPhase: String, chapter: String) {
        phase = nextPhase
        chapterTitle = chapter
        if (phase == "paused") {
            releaseFocus()
            if (wakeLock.isHeld) wakeLock.release()
        }
        publish()
    }

    private fun publish() {
        val paused = phase == "paused"
        val state = when (phase) {
            "playing" -> PlaybackState.STATE_PLAYING
            "loading" -> PlaybackState.STATE_BUFFERING
            else -> PlaybackState.STATE_PAUSED
        }
        val actions = PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or
            if (paused) PlaybackState.ACTION_PLAY else PlaybackState.ACTION_PAUSE
        mediaSession.setPlaybackState(
            PlaybackState.Builder().setActions(actions)
                .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (paused) 0f else 1f)
                .addCustomAction(ACTION_END, "结束听书", android.R.drawable.ic_menu_close_clear_cancel)
                .build(),
        )
        mediaSession.setMetadata(
            MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, bookTitle)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, chapterTitle)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "墨屿听书").build(),
        )
        val notification = buildNotification(paused)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(paused: Boolean): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        val label = if (paused) "已暂停" else if (phase == "loading") "正在准备语音" else "正在朗读"
        return builder.setSmallIcon(R.drawable.ic_tts_notification)
            .setContentTitle(bookTitle).setContentText(listOf(chapterTitle, label).filter { it.isNotEmpty() }.joinToString(" · "))
            .setContentIntent(openReaderIntent()).setDeleteIntent(actionIntent("stop"))
            .setCategory(Notification.CATEGORY_TRANSPORT).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(!paused).setOnlyAlertOnce(true).setShowWhen(false)
            .addAction(Notification.Action.Builder(
                Icon.createWithResource(this, if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause),
                if (paused) "继续朗读" else "暂停朗读", actionIntent(if (paused) "play" else "pause"),
            ).build())
            .addAction(Notification.Action.Builder(
                Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                "结束听书", actionIntent("stop"),
            ).build())
            .setStyle(Notification.MediaStyle().setMediaSession(mediaSession.sessionToken).setShowActionsInCompactView(0, 1))
            .build()
    }

    private fun actionIntent(action: String): PendingIntent = PendingIntent.getService(
        this, 0, Intent(this, ReaderTtsPlaybackService::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun openReaderIntent(): PendingIntent = PendingIntent.getActivity(
        this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun finish(result: MethodChannel.Result? = null) {
        if (result != null) pendingStop = result
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        sendCommand("stop")
        finish()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        instance = null
        unregisterReceiver(noisyReceiver)
        releaseFocus()
        if (wakeLock.isHeld) wakeLock.release()
        mediaSession.isActive = false
        mediaSession.release()
        notifications.cancel(NOTIFICATION_ID)
        pendingStart?.error("playback_stopped", "听书服务已结束", null)
        pendingStart = null
        pendingStop?.success(null)
        pendingStop = null
        super.onDestroy()
    }
}
