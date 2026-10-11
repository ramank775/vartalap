package com.one9x.vartalap

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.File

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
        // Open a downloaded attachment in whatever app handles its type.
        // false = nothing installed can; the caller offers "Save to…".
        MethodChannel(messenger, "vartalap/files")
            .setMethodCallHandler { call, result ->
                val uri = FileProvider.getUriForFile(
                    this, "$packageName.files", File(call.argument<String>("path")!!)
                )
                val view = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, call.argument<String>("mime"))
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                result.success(try {
                    startActivity(view); true
                } catch (e: ActivityNotFoundException) {
                    false
                })
            }
    }
}
