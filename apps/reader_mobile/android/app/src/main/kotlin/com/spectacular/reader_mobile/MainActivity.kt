package com.spectacular.reader_mobile

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var readerChannel: MethodChannel? = null
    private var volumeKeyPaging = false
    private var epubExport: EpubExportHandler? = null
    private var battery: ReaderBatteryHandler? = null
    private var batteryChannel: EventChannel? = null
    private var onlineSourceLogin: OnlineSourceLoginHandler? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var showStatusBar = true
    private var showNavigationBar = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        epubExport = EpubExportHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.spectacular.reader_mobile/epub_export").setMethodCallHandler(epubExport)
        battery = ReaderBatteryHandler(this)
        batteryChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.spectacular.reader_mobile/battery").also { it.setStreamHandler(battery) }
        onlineSourceLogin = OnlineSourceLoginHandler(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        readerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.spectacular.reader_mobile/reader",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    "setVolumeKeyPaging" -> {
                        volumeKeyPaging = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    "getBatteryStatus" -> result.success(battery?.snapshot())
                    "acquireMulticastLock" -> {
                        acquireMulticastLock()
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    "setSystemBars" -> {
                        val bars = call.arguments as? Map<*, *>
                        val statusBar = bars?.get("statusBar") as? Boolean
                        val navigationBar = bars?.get("navigationBar") as? Boolean
                        if (statusBar == null || navigationBar == null) {
                            result.error("invalid_system_bars", "系统栏参数必须是布尔值", null)
                        } else {
                            showStatusBar = statusBar
                            showNavigationBar = navigationBar
                            applySystemBars()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (onlineSourceLogin?.onActivityResult(requestCode, resultCode, data) == true) return
        if (epubExport?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        releaseMulticastLock()
        onlineSourceLogin?.dispose()
        epubExport?.dispose()
        batteryChannel?.setStreamHandler(null)
        battery?.dispose()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applySystemBars()
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return
        multicastLock = wifi.createMulticastLock("spectacular-reamicro-discovery").also {
            it.setReferenceCounted(false)
            it.acquire()
        }
    }

    private fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        if (lock.isHeld) lock.release()
        multicastLock = null
    }

    private fun applySystemBars() {
        applyEdgeToEdge(window)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (showStatusBar) {
            controller.show(WindowInsetsCompat.Type.statusBars())
        } else {
            controller.hide(WindowInsetsCompat.Type.statusBars())
        }
        if (showNavigationBar) {
            controller.show(WindowInsetsCompat.Type.navigationBars())
        } else {
            controller.hide(WindowInsetsCompat.Type.navigationBars())
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (volumeKeyPaging &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            readerChannel?.invokeMethod(
                "volumeKeyPage",
                if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) "next" else "previous",
            )
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun setKeepScreenOn(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
