package com.spectacular.reader_mobile

import android.graphics.ImageDecoder
import android.os.Build
import android.util.Log
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.ByteBuffer

/** WebView 不支持 HEIC；保留原签名地址，在本机解码成 PNG。 */
object OnlineReviewImageLoader {
    fun load(request: WebResourceRequest): WebResourceResponse? {
        if (Build.VERSION.SDK_INT < 28 || request.method != "GET") return null
        val uri = request.url
        if (uri.scheme !in listOf("http", "https") ||
            !uri.path.orEmpty().endsWith(".heic", ignoreCase = true)) return null
        return runCatching {
            var target = URI(uri.toString())
            var connection: HttpURLConnection? = null
            try {
                for (redirect in 0..5) {
                    val next = target.toURL().openConnection() as HttpURLConnection
                    connection = next
                    next.instanceFollowRedirects = false
                    next.connectTimeout = 10000
                    next.readTimeout = 10000
                    // 跨域重定向不带敏感凭据；图片格式由原 URL 和响应决定。
                    request.requestHeaders.forEach { (name, value) ->
                        if (!name.equals("Cookie", true) && !name.equals("Authorization", true)) {
                            next.setRequestProperty(name, value)
                        }
                    }
                    if (next.responseCode !in listOf(301, 302, 303, 307, 308)) break
                    val location = next.getHeaderField("Location") ?: return null
                    val resolved = target.resolve(location)
                    if (resolved.scheme !in listOf("http", "https") || redirect == 5) return null
                    next.disconnect()
                    target = resolved
                }
                val response = connection ?: return null
                if (response.responseCode !in 200..299) {
                    Log.w("OnlineReviewImage", "头像请求失败：HTTP ${response.responseCode}")
                    return null
                }
                val limit = 8 * 1024 * 1024
                val bytes = response.inputStream.use { input ->
                    val buffer = ByteArray(8192)
                    val data = ByteArrayOutputStream()
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (data.size() + count > limit) return null
                        data.write(buffer, 0, count)
                    }
                    data.toByteArray()
                }
                val image = ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(bytes))) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val largest = maxOf(info.size.width, info.size.height)
                    if (largest > 512) decoder.setTargetSampleSize((largest + 511) / 512)
                }
                val output = ByteArrayOutputStream()
                try {
                    image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
                } finally {
                    image.recycle()
                }
                WebResourceResponse("image/png", null, ByteArrayInputStream(output.toByteArray()))
            } finally {
                connection?.disconnect()
            }
        }.onFailure {
            Log.w("OnlineReviewImage", "头像解码失败：${it.javaClass.simpleName}")
        }.getOrNull()
    }
}
