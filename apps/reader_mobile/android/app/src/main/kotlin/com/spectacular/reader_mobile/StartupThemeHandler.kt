package com.spectacular.reader_mobile

import android.app.Activity
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.os.Build

/** 首帧前读取小型配色缓存；图标只由系统启动窗口绘制。 */
internal class StartupThemeHandler(private val activity: Activity) {
    private val cache = activity.getSharedPreferences("startup_theme", Activity.MODE_PRIVATE)

    fun snapshot(): Map<String, Any?>? {
        if (!cache.contains("mode")) return null
        return mapOf(
            "mode" to cache.getString("mode", "system"),
            "preset" to cache.getString("preset", null),
            "wallpaperEnabled" to cache.getBoolean("wallpaperEnabled", false),
            "seed" to if (cache.contains("seed")) cache.getLong("seed", 0L) else null,
        )
    }

    fun save(values: Map<*, *>) {
        val editor = cache.edit()
        editor.putString("mode", values["mode"] as? String ?: "system")
        editor.putString("preset", values["preset"] as? String)
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
            "${prefix}Background", activity.getColor(R.color.startup_background),
        )
        activity.window.setBackgroundDrawable(ColorDrawable(background))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // 系统启动层在 Flutter 首帧绘制后直接移除，避免再次淡出露出窗口底色。
            activity.splashScreen.setOnExitAnimationListener { splash -> splash.remove() }
        }
    }

}
