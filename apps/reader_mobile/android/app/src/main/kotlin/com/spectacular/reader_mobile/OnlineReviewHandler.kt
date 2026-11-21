package com.spectacular.reader_mobile

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowInsets
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.widget.LinearLayout
import android.widget.FrameLayout
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
            var bottomInset = 0
            var pageReady = false
            fun applyScrollInset(view: WebView) {
                if (!pageReady) return
                val cssBottom = bottomInset / activity.resources.displayMetrics.density
                // 末尾留白参与网页滚动，视口本身仍延伸到透明导航栏下。
                view.evaluateJavascript("""
                    (function(){
                      var style=document.getElementById('reader-review-insets');
                      if(!style){style=document.createElement('style');
                        style.id='reader-review-insets';document.head.appendChild(style);}
                      style.textContent='body::after{content:"";display:block;clear:both;height:${cssBottom}px;}html{scroll-padding-bottom:${cssBottom}px;}';
                    })();
                """.trimIndent(), null)
            }
            cookies.setAcceptCookie(cookieEnabled)
            val cookie = args["cookie"] as? String ?: ""
            val sheet = Dialog(activity, R.style.OnlineReviewTheme)
            sheet.requestWindowFeature(Window.FEATURE_NO_TITLE)
            sheet.setCanceledOnTouchOutside(true)
            if (cookieEnabled) {
                cookie.split(';').map(String::trim).filter(String::isNotEmpty).forEach {
                    cookies.setCookie(url, it)
                }
                cookies.flush()
            }
            val web = WebView(activity).apply {
                setBackgroundColor(Color.rgb(247, 247, 248))
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                headers.entries.firstOrNull { it.key.equals("User-Agent", true) }
                    ?.value?.let { settings.userAgentString = it }
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                webChromeClient = object : WebChromeClient() {
                    override fun onCloseWindow(window: WebView?) {
                        sheet.dismiss()
                    }
                }
                webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest): WebResourceResponse? =
                        OnlineReviewImageLoader.load(request)

                    override fun onPageFinished(view: WebView?, pageUrl: String?) {
                        pageReady = true
                        view?.let { applyScrollInset(it) }
                        if (html.isBlank() && preload.isNotBlank()) {
                            view?.evaluateJavascript(preload, null)
                        }
                    }
                }
            }
            cookies.setAcceptThirdPartyCookies(web, cookieEnabled)
            val root = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                val radius = 16f * resources.displayMetrics.density
                background = GradientDrawable().apply {
                    setColor(Color.rgb(247, 247, 248))
                    cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
                }
                clipToOutline = true
                addView(web, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f,
                ))
            }
            // 全屏透明容器负责遮罩，底部面板在容器内定位，避免系统给浮动窗预留底栏。
            val container = FrameLayout(activity).apply {
                setOnClickListener { sheet.dismiss() }
                addView(root, FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, Gravity.BOTTOM,
                ))
            }
            root.isClickable = true
            sheet.setContentView(container)
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
            val percent = config?.optDouble("heightPercentage",
                config.optDouble("height", 0.8))?.let {
                if (it > 1) it / 100 else it
            }?.takeIf { it.isFinite() }?.coerceIn(0.3, 0.95) ?: 0.8
            sheet.window?.apply {
                setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
                decorView.setPadding(0, 0, 0, 0)
                addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
                clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS or
                    WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
                attributes = attributes.apply {
                    dimAmount = 0.32f
                    if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
                }
                if (Build.VERSION.SDK_INT >= 30) {
                    setDecorFitsSystemWindows(false)
                    insetsController?.setSystemBarsAppearance(
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS or
                            android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS or
                            android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    decorView.systemUiVisibility =
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                }
                @Suppress("DEPRECATION")
                navigationBarColor = Color.TRANSPARENT
                @Suppress("DEPRECATION")
                statusBarColor = Color.TRANSPARENT
                if (Build.VERSION.SDK_INT >= 29) {
                    isNavigationBarContrastEnforced = false
                    isStatusBarContrastEnforced = false
                }
                setGravity(Gravity.FILL)
                setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
                setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT)
            }
            container.setOnApplyWindowInsetsListener { _, insets ->
                bottomInset = if (Build.VERSION.SDK_INT >= 30) {
                    insets.getInsets(WindowInsets.Type.navigationBars()).bottom
                } else {
                    @Suppress("DEPRECATION")
                    insets.systemWindowInsetBottom
                }
                applyScrollInset(web)
                val top = if (Build.VERSION.SDK_INT >= 30) {
                    insets.getInsets(WindowInsets.Type.statusBars()).top
                } else {
                    @Suppress("DEPRECATION")
                    insets.systemWindowInsetTop
                }
                val height = (container.height * percent).toInt()
                    .coerceAtMost((container.height - top).coerceAtLeast(0))
                root.layoutParams = (root.layoutParams as FrameLayout.LayoutParams).apply {
                    this.height = height
                }
                insets
            }
            container.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                val height = (container.height * percent).toInt()
                if (root.layoutParams.height != height) {
                    root.layoutParams = (root.layoutParams as FrameLayout.LayoutParams).apply {
                        this.height = height
                    }
                }
            }
            root.requestApplyInsets()
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
