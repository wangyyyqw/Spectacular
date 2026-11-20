package com.spectacular.reader_mobile

import android.app.Activity
import android.content.Intent
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
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
        if (call.method != "saveFile" && call.method != "saveToDownloads") {
            result.notImplemented(); return
        }
        if (pending != null) { result.error("E_EXPORT_BUSY", "请先完成当前导出", null); return }
        val path = call.argument<String>("sourcePath")
        val name = call.argument<String>("fileName")
        if (path == null || name.isNullOrBlank() || !File(path).isFile) {
            result.error("E_EXPORT_SOURCE", "待导出的 EPUB 不存在", null)
            return
        }
        pending = Pending(File(path), result)
        if (call.method == "saveToDownloads" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveToDownloads(pending!!, name)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/epub+zip"
            putExtra(Intent.EXTRA_TITLE, name)
            if (call.method == "saveToDownloads" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents", "primary:Download"))
            }
        }
        try { activity.startActivityForResult(intent, REQUEST_CODE) }
        catch (error: Exception) {
            pending = null
            result.error("E_EXPORT_PICKER", "无法打开文件保存窗口", error.message)
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun saveToDownloads(request: Pending, name: String) {
        worker.execute {
            val resolver = activity.contentResolver
            var uri: Uri? = null
            var failure: Exception? = null
            try {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/epub+zip")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw java.io.IOException("无法创建下载文件")
                copySource(request.source, uri)
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                if (resolver.update(uri, values, null, null) != 1) {
                    throw java.io.IOException("无法完成下载文件保存")
                }
            } catch (error: Exception) {
                uri?.let { runCatching { resolver.delete(it, null, null) } }
                failure = error
            }
            activity.runOnUiThread {
                if (pending === request) {
                    pending = null
                    if (failure == null) request.result.success(uri.toString())
                    else request.result.error("E_EXPORT_WRITE", "无法保存到下载文件夹", failure.message)
                }
            }
        }
    }

    private fun copySource(source: File, uri: Uri) {
        source.inputStream().use { input ->
            val output = activity.contentResolver.openOutputStream(uri, "wt")
                ?: throw java.io.IOException("无法打开目标文件")
            output.use { input.copyTo(it, 64 * 1024); it.flush() }
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
                copySource(request.source, uri)
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
