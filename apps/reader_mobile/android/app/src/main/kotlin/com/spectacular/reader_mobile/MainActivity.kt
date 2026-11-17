package com.spectacular.reader_mobile

import android.content.Intent
import android.content.Context
import android.net.wifi.WifiManager
import android.view.KeyEvent
import android.view.WindowManager
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
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        epubExport = EpubExportHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.spectacular.reader_mobile/epub_export").setMethodCallHandler(epubExport)
        battery = ReaderBatteryHandler(this)
        batteryChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.spectacular.reader_mobile/battery").also { it.setStreamHandler(battery) }
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
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (epubExport?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        releaseMulticastLock()
        epubExport?.dispose()
        batteryChannel?.setStreamHandler(null)
        battery?.dispose()
        super.onDestroy()
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
