package com.one9x.vartalap

import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // SIM country for the phone screen's default country; needs no permission.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vartalap/sim")
            .setMethodCallHandler { _, result ->
                val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
                result.success(tm.simCountryIso.ifEmpty { tm.networkCountryIso })
            }
    }
}
