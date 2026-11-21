package com.spectacular.reader_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** 下载进度和完成结果沿用同一通知，点击返回应用。 */
class OnlineDownloadHandler(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private var askedPermission = false
    private val channel = MethodChannel(messenger, "com.spectacular.reader_mobile/online_download")
    init {
        manager.createNotificationChannel(
            NotificationChannel("online_download", "图书下载", NotificationManager.IMPORTANCE_LOW)
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "update") {
                result.notImplemented()
            } else {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                update(args)
                result.success(null)
            }
        }
    }
    private fun update(args: Map<*, *>) {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (!askedPermission) {
                askedPermission = true
                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7021)
            }
            return
        }
        val id = (args["id"] as? Number)?.toInt() ?: return
        val completed = (args["completed"] as? Number)?.toInt() ?: 0
        val total = (args["total"] as? Number)?.toInt() ?: 0
        val done = args["done"] == true
        val intent = Intent(activity, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(activity, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(activity, "online_download")
            .setSmallIcon(if (done) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_sys_download)
            .setContentTitle(args["title"]?.toString() ?: "图书下载")
            .setContentText(args["message"]?.toString() ?: "")
            .setContentIntent(pending).setOnlyAlertOnce(true)
            .setOngoing(!done).setAutoCancel(done)
        if (!done) notification.setProgress(total, completed, total <= 0)
        manager.notify(id, notification.build())
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
