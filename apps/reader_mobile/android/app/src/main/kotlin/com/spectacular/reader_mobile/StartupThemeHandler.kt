package com.spectacular.reader_mobile

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import androidx.core.graphics.PathParser
import org.xmlpull.v1.XmlPullParser

/** 首帧前读取小型配色缓存，并直接绘制现有矢量标识，不等待 Flutter 或数据库。 */
internal class StartupThemeHandler(private val activity: Activity) {
    private val cache = activity.getSharedPreferences("startup_theme", Activity.MODE_PRIVATE)

    fun snapshot(): Map<String, Any?>? {
        if (!cache.contains("mode")) return null
        return mapOf(
            "mode" to cache.getString("mode", "system"),
            "wallpaperEnabled" to cache.getBoolean("wallpaperEnabled", false),
            "seed" to if (cache.contains("seed")) cache.getLong("seed", 0L) else null,
        )
    }

    fun save(values: Map<*, *>) {
        val editor = cache.edit()
        editor.putString("mode", values["mode"] as? String ?: "system")
        editor.putBoolean("wallpaperEnabled", values["wallpaperEnabled"] == true)
        val seed = values["seed"] as? Number
        if (seed == null) editor.remove("seed") else editor.putLong("seed", seed.toLong())
        for (key in listOf("lightBackground", "darkBackground", "lightForeground", "darkForeground")) {
            (values[key] as? Number)?.let { editor.putInt(key, it.toInt()) }
        }
        editor.apply()
    }

    fun applyWindowBackground() {
        val systemDark = activity.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val dark = when (cache.getString("mode", "system")) {
            "dark" -> true
            "light" -> false
            else -> systemDark
        }
        val prefix = if (dark) "dark" else "light"
        val background = cache.getInt(
            "${prefix}Background", if (dark) 0xFF1B1D1F.toInt() else 0xFFF6F6F4.toInt(),
        )
        val foreground = cache.getInt(
            "${prefix}Foreground", if (dark) 0xFFE7E8E4.toInt() else 0xFF222427.toInt(),
        )
        activity.window.setBackgroundDrawable(StartupDrawable(background, foreground))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // 系统启动层在 Flutter 首帧绘制后直接移除，避免再次淡出露出窗口底色。
            activity.splashScreen.setOnExitAnimationListener { splash -> splash.remove() }
        }
    }

    private inner class StartupDrawable(
        private val background: Int,
        foreground: Int,
    ) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = foreground }
        private val paths = mutableListOf<Path>()
        private val logoBounds = RectF()
        private val density = activity.resources.displayMetrics.density

        init {
            val parser = activity.resources.getXml(R.drawable.ic_launcher_monochrome)
            try {
                var event = parser.eventType
                while (event != XmlPullParser.END_DOCUMENT) {
                    if (event == XmlPullParser.START_TAG && parser.name == "path") {
                        val data = parser.getAttributeValue(
                            "http://schemas.android.com/apk/res/android", "pathData",
                        )
                        PathParser.createPathFromPathData(data)?.let { path ->
                            paths.add(path)
                            val bounds = RectF()
                            path.computeBounds(bounds, true)
                            logoBounds.union(bounds)
                        }
                    }
                    event = parser.next()
                }
            } finally {
                parser.close()
            }
        }

        override fun draw(canvas: Canvas) {
            canvas.drawColor(background)
            val scale = 88f * density / maxOf(logoBounds.width(), logoBounds.height())
            canvas.save()
            canvas.translate(bounds.exactCenterX(), bounds.exactCenterY() - 23f * density)
            canvas.scale(scale, scale)
            canvas.translate(-logoBounds.centerX(), -logoBounds.centerY())
            for (path in paths) canvas.drawPath(path, paint)
            canvas.restore()
            paint.textSize = 22f * density
            paint.textAlign = Paint.Align.CENTER
            canvas.drawText(
                "阅微 Extend", bounds.exactCenterX(), bounds.exactCenterY() + 55f * density, paint,
            )
        }

        override fun setAlpha(alpha: Int) { paint.alpha = alpha }
        override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter }
        @Deprecated("由系统兼容接口要求")
        override fun getOpacity(): Int = PixelFormat.OPAQUE
    }
}
