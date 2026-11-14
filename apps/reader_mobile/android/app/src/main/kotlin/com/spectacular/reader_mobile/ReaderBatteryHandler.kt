package com.spectacular.reader_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.plugin.common.EventChannel

/** 查询与推送使用同一份系统电池状态，已充满且仍接电时保留充电标记。 */
class ReaderBatteryHandler(private val context: Context) : EventChannel.StreamHandler {
    private val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
    private var receiver: BroadcastReceiver? = null

    fun snapshot(battery: Intent? = context.registerReceiver(null, filter)): Map<String, Any?>? {
        battery ?: return null
        val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val plugged = battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = when {
            plugged == 0 -> false
            status == BatteryManager.BATTERY_STATUS_CHARGING -> true
            status == BatteryManager.BATTERY_STATUS_FULL && plugged > 0 -> true
            status == BatteryManager.BATTERY_STATUS_DISCHARGING ||
                status == BatteryManager.BATTERY_STATUS_NOT_CHARGING -> false
            else -> null
        }
        return mapOf(
            "level" to if (level >= 0 && scale > 0) {
                (level * 100 / scale).coerceIn(0, 100)
            } else {
                null
            },
            "charging" to charging,
        )
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        dispose()
        val listener = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                events.success(snapshot(intent))
            }
        }
        receiver = listener
        // 系统粘性广播会立即补发当前状态，也覆盖查询与订阅之间的变化。
        context.registerReceiver(listener, filter)
    }

    override fun onCancel(arguments: Any?) = dispose()

    fun dispose() {
        receiver?.let(context::unregisterReceiver)
        receiver = null
    }
}
