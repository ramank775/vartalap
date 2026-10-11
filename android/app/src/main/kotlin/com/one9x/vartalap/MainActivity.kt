package com.one9x.vartalap

import android.content.pm.PackageManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // SIM country for the phone screen's default country; needs no permission.
        MethodChannel(messenger, "vartalap/sim")
            .setMethodCallHandler { _, result ->
                val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
                result.success(tm.simCountryIso.ifEmpty { tm.networkCountryIso })
            }
        // The push chooser: is Google push possible (gms build with Play
        // services), and what is a distributor called. Distributors are
        // visible to us through the UnifiedPush connector's <queries>.
        MethodChannel(messenger, "vartalap/push")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "googleAvailable" -> result.success(GooglePush.available(this))
                    "appLabel" -> result.success(try {
                        packageManager.getApplicationLabel(
                            packageManager.getApplicationInfo(call.arguments as String, 0)
                        ).toString()
                    } catch (e: PackageManager.NameNotFoundException) {
                        null
                    })
                    else -> result.notImplemented()
                }
            }
    }
}
