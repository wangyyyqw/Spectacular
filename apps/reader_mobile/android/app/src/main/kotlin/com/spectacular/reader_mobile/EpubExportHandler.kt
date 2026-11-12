package com.spectacular.reader_mobile

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** SAF 接收的 URI 只交给 ContentResolver；大书不经过 Flutter 字节通道。 */
class EpubExportHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private data class Pending(val source: File, val result: MethodChannel.Result)
    private var pending: Pending? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveFile") { result.notImplemented(); return }
        if (pending != null) { result.error("E_EXPORT_BUSY", "请先完成当前导出", null); return }
        val path = call.argument<String>("sourcePath")
        val name = call.argument<String>("fileName")
        if (path == null || name.isNullOrBlank() || !File(path).isFile) {
            result.error("E_EXPORT_SOURCE", "待导出的 EPUB 不存在", null)
            return
        }
        pending = Pending(File(path), result)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/epub+zip"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try { activity.startActivityForResult(intent, REQUEST_CODE) }
        catch (error: Exception) {
            pending = null
            result.error("E_EXPORT_PICKER", "无法打开文件保存窗口", error.message)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val request = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            request.result.success(null)
            return true
        }
        worker.execute {
            try {
                request.source.inputStream().use { input ->
                    val output = activity.contentResolver.openOutputStream(uri, "wt")
                        ?: throw java.io.IOException("无法打开目标文件")
                    output.use { input.copyTo(it, 64 * 1024); it.flush() }
                }
                activity.runOnUiThread {
                    if (pending === request) {
                        pending = null
                        request.result.success(uri.toString())
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    if (pending === request) {
                        pending = null
                        request.result.error("E_EXPORT_WRITE", "导出未完成，请重新选择保存位置", error.message)
                    }
                }
            }
        }
        return true
    }

    fun dispose() {
        pending?.result?.error("E_EXPORT_CLOSED", "导出窗口已关闭，请重试", null)
        pending = null
        worker.shutdownNow()
    }

    companion object { private const val REQUEST_CODE = 8421 }
}
