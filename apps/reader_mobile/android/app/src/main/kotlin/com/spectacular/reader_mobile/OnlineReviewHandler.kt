package com.spectacular.reader_mobile

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** 段评面板只持有本次网页，关闭后销毁，不改动阅读导航与进度。 */
class OnlineReviewHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private var dialog: Dialog? = null
    private val channel = MethodChannel(
        messenger, "com.spectacular.reader_mobile/online_review",
    ).also { channel ->
        channel.setMethodCallHandler { call, result ->
            if (call.method != "show") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (dialog != null) {
                result.error("review_busy", "段评面板已打开", null)
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val url = args["url"] as? String ?: ""
            if (!url.startsWith("https://") && !url.startsWith("http://")) {
                result.error("review_url", "段评地址无效", null)
                return@setMethodCallHandler
            }
            val html = args["html"] as? String ?: ""
            val preload = args["preloadJs"] as? String ?: ""
            val headers = (args["headers"] as? Map<*, *>)?.entries?.associate {
                it.key.toString() to it.value.toString()
            } ?: emptyMap()
            val cookieEnabled = args["enabledCookieJar"] != false
            val cookies = CookieManager.getInstance()
            val previousAcceptCookie = cookies.acceptCookie()
            cookies.setAcceptCookie(cookieEnabled)
            val cookie = args["cookie"] as? String ?: ""
            if (cookieEnabled) {
                cookie.split(';').map(String::trim).filter(String::isNotEmpty).forEach {
                    cookies.setCookie(url, it)
                }
                cookies.flush()
            }
            val web = WebView(activity).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                headers.entries.firstOrNull { it.key.equals("User-Agent", true) }
                    ?.value?.let { settings.userAgentString = it }
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, pageUrl: String?) {
                        if (html.isBlank() && preload.isNotBlank()) {
                            view?.evaluateJavascript(preload, null)
                        }
                    }
                }
            }
            cookies.setAcceptThirdPartyCookies(web, cookieEnabled)
            val sheet = Dialog(activity)
            val root = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(Color.WHITE)
                addView(Button(activity).apply {
                    text = "关闭段评"
                    setOnClickListener { sheet.dismiss() }
                })
                addView(web, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f,
                ))
            }
            sheet.setContentView(root)
            sheet.setOnDismissListener {
                cookies.flush()
                result.success(mapOf(
                    "url" to (web.url ?: url),
                    "cookie" to if (cookieEnabled) cookies.getCookie(web.url ?: url).orEmpty() else "",
                ))
                cookies.setAcceptCookie(previousAcceptCookie)
                root.removeView(web)
                web.stopLoading()
                web.destroy()
                dialog = null
            }
            dialog = sheet
            sheet.show()
            val config = runCatching { JSONObject(args["config"] as? String ?: "{}") }.getOrNull()
            val percent = config?.optDouble("height", 0.7)?.let {
                if (it > 1) it / 100 else it
            }?.takeIf { it.isFinite() }?.coerceIn(0.3, 1.0) ?: 0.7
            sheet.window?.apply {
                setGravity(Gravity.BOTTOM)
                setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
                setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
                    (activity.resources.displayMetrics.heightPixels * percent).toInt())
            }
            if (html.isNotBlank()) {
                val injection = if (preload.isBlank()) "" else {
                    "<script>${preload.replace("</script", "<\\/script", ignoreCase = true)}</script>"
                }
                val head = Regex("<head\\b[^>]*>", RegexOption.IGNORE_CASE).find(html)
                val document = if (head != null) {
                    html.substring(0, head.range.last + 1) + injection +
                        html.substring(head.range.last + 1)
                } else injection + html
                web.loadDataWithBaseURL(url, document, "text/html", "UTF-8", url)
            } else {
                web.loadUrl(url, headers)
            }
        }
    }

    fun dispose() {
        dialog?.dismiss()
        channel.setMethodCallHandler(null)
    }
}
