package com.spectacular.reader_mobile

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class OnlineSourceLoginHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private var pending: MethodChannel.Result? = null

    private val channel = MethodChannel(
        messenger,
        "com.spectacular.reader_mobile/online_source_login",
    ).also { it.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "login") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("login_busy", "已有登录页正在打开", null)
            return
        }
        val arguments = call.arguments as? Map<*, *>
        val url = (arguments?.get("url") as? String).orEmpty().trim()
        val title = (arguments?.get("title") as? String).orEmpty()
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            result.error("login_url", "登录地址无效", null)
            return
        }
        pending = result
        val intent = Intent(activity, OnlineSourceLoginActivity::class.java).apply {
            putExtra(OnlineSourceLoginActivity.EXTRA_URL, url)
            putExtra(OnlineSourceLoginActivity.EXTRA_TITLE, title)
        }
        activity.startActivityForResult(intent, REQUEST_CODE)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }
        result.success(
            mapOf(
                "cookie" to data?.getStringExtra(OnlineSourceLoginActivity.EXTRA_COOKIE).orEmpty(),
                "url" to data?.getStringExtra(OnlineSourceLoginActivity.EXTRA_FINAL_URL).orEmpty(),
            ),
        )
        return true
    }

    fun dispose() {
        pending?.error("login_cancelled", "登录页已关闭", null)
        pending = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val REQUEST_CODE = 0x5101
    }
}
