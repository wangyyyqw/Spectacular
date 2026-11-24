package com.spectacular.reader_mobile

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 阅读页的唯一听书控制器与 Android 媒体会话之间的连接。 */
class ReaderTtsPlaybackHandler(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val channel = MethodChannel(
        messenger,
        "com.spectacular.reader_mobile/tts_playback",
    )

    init {
        channel.setMethodCallHandler(this)
        ReaderTtsPlaybackService.channel = channel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("bookTitle")
                    if (title == null) {
                        result.error("invalid_playback", "听书缺少书名", null)
                    } else {
                        ReaderTtsPlaybackService.start(context, title, result)
                    }
                }
                "activate" -> {
                    val service = ReaderTtsPlaybackService.instance
                    if (service == null) {
                        result.error("playback_stopped", "听书服务已结束，请重新开始", null)
                    } else {
                        service.activate(result)
                    }
                }
                "update" -> update(call, result)
                "stop" -> {
                    val service = ReaderTtsPlaybackService.instance
                    if (service == null) result.success(null) else service.finish(result)
                }
                else -> result.notImplemented()
            }
        } catch (error: RuntimeException) {
            result.error("playback_service_error", "后台听书服务不可用：${error.message}", null)
        }
    }

    private fun update(call: MethodCall, result: MethodChannel.Result) {
        val phase = call.argument<String>("phase")
        val chapter = call.argument<String>("chapterTitle")
        if (phase !in setOf("loading", "playing", "paused") || chapter == null) {
            result.error("invalid_playback", "听书状态或章节参数无效", null)
            return
        }
        ReaderTtsPlaybackService.instance?.update(phase!!, chapter)
        result.success(null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (ReaderTtsPlaybackService.channel === channel) {
            ReaderTtsPlaybackService.channel = null
            context.stopService(Intent(context, ReaderTtsPlaybackService::class.java))
        }
    }
}
