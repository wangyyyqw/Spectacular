package com.spectacular.reader_mobile

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class OnlineSourceLoginActivity : Activity() {
    private lateinit var webView: WebView
    private var startUrl = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startUrl = intent.getStringExtra(EXTRA_URL).orEmpty().trim()
        if (!startUrl.startsWith("http://") && !startUrl.startsWith("https://")) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val density = resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(8), dp(8))
        }
        val title = TextView(this).apply {
            text = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "书源登录" }
            textSize = 16f
            setTextColor(Color.rgb(32, 32, 32))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        bar.addView(
            title,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        bar.addView(
            Button(this).apply {
                text = "取消"
                setOnClickListener {
                    setResult(RESULT_CANCELED)
                    finish()
                }
            },
        )
        bar.addView(
            Button(this).apply {
                text = "完成"
                setOnClickListener { finishWithCookies() }
            },
        )
        root.addView(bar)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode =
                WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    CookieManager.getInstance().flush()
                }
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        root.addView(
            webView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        setContentView(root)
        webView.loadUrl(startUrl)
    }

    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
            return
        }
        setResult(RESULT_CANCELED)
        finish()
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }

    private fun finishWithCookies() {
        val manager = CookieManager.getInstance()
        manager.flush()
        val cookies = linkedMapOf<String, String>()
        val urls = linkedSetOf<String>()
        webView.url?.takeIf { it.isNotBlank() }?.let(urls::add)
        urls.add(startUrl)
        Uri.parse(startUrl).let { uri ->
            if (uri.scheme != null && uri.host != null) {
                urls.add("${uri.scheme}://${uri.host}/")
            }
        }
        for (url in urls) {
            val header = manager.getCookie(url).orEmpty()
            for (part in header.split(';')) {
                val text = part.trim()
                val index = text.indexOf('=')
                if (index <= 0) continue
                val name = text.substring(0, index).trim()
                val value = text.substring(index + 1).trim()
                if (name.isNotEmpty() && value.isNotEmpty()) {
                    cookies[name] = value
                }
            }
        }
        val data = Intent().apply {
            putExtra(EXTRA_COOKIE, cookies.entries.joinToString("; ") {
                "${it.key}=${it.value}"
            })
            putExtra(EXTRA_FINAL_URL, webView.url ?: startUrl)
        }
        setResult(RESULT_OK, data)
        finish()
    }

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_COOKIE = "cookie"
        const val EXTRA_FINAL_URL = "finalUrl"
    }
}
