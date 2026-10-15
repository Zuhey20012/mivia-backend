package com.malvoya.courier

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Battery optimisation check for the "before you go online" list. Only reads the state and
        // opens the system list; it does not use REQUEST_IGNORE_BATTERY_OPTIMIZATIONS.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.malvoya.courier/battery").setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        result.success(true)
                    } else {
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(power.isIgnoringBatteryOptimizations(packageName))
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
