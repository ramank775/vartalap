package com.one9x.vartalap

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.CancellationSignal
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.location.LocationManagerCompat
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
        // Where the phone is now, from the platform LocationManager —
        // not Play services' fused provider, so FOSS builds have it too.
        // null = location off, permission missing, or no fix in time.
        MethodChannel(messenger, "vartalap/location")
            .setMethodCallHandler { _, result ->
                val lm = getSystemService(LOCATION_SERVICE) as LocationManager
                // "fused" here is the platform's own (Android 12+), not
                // Play services'; GPS alone can take 30 s indoors.
                val provider = listOf("fused", LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                    .firstOrNull { lm.allProviders.contains(it) && lm.isProviderEnabled(it) }
                if (provider == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                try {
                    // A fix from the last two minutes is good enough to share.
                    val recent = lm.getLastKnownLocation(provider)
                    if (recent != null && System.currentTimeMillis() - recent.time < 120_000) {
                        result.success(mapOf(
                            "lat" to recent.latitude, "lng" to recent.longitude, "accuracy" to recent.accuracy.toDouble()
                        ))
                        return@setMethodCallHandler
                    }
                    LocationManagerCompat.getCurrentLocation(
                        lm, provider, CancellationSignal(), ContextCompat.getMainExecutor(this)
                    ) { loc ->
                        result.success(loc?.let {
                            mapOf("lat" to it.latitude, "lng" to it.longitude, "accuracy" to it.accuracy.toDouble())
                        })
                    }
                } catch (e: SecurityException) {
                    result.success(null)
                }
            }
        // Pre-filled hand-offs to the system apps, from shared contact
        // and event cards. false = no app installed takes it.
        MethodChannel(messenger, "vartalap/intents")
            .setMethodCallHandler { call, result ->
                val intent = when (call.method) {
                    "addEvent" -> Intent(Intent.ACTION_INSERT)
                        .setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("begin")!!.toLong())
                        .putExtra(CalendarContract.Events.EVENT_LOCATION, call.argument<String>("location"))
                        .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
                        .apply {
                            call.argument<Number>("end")?.let {
                                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it.toLong())
                            }
                        }
                    // The plain Insert extras: every contacts app reads
                    // these, unlike a structured name inside Insert.DATA.
                    "addContact" -> Intent(Intent.ACTION_INSERT, ContactsContract.Contacts.CONTENT_URI)
                        .putExtra(ContactsContract.Intents.Insert.NAME, call.argument<String>("name"))
                        .putExtra(ContactsContract.Intents.Insert.EMAIL, call.argument<String>("email"))
                        .apply {
                            val phones = call.argument<List<String>>("phones").orEmpty()
                            listOf(
                                ContactsContract.Intents.Insert.PHONE,
                                ContactsContract.Intents.Insert.SECONDARY_PHONE,
                                ContactsContract.Intents.Insert.TERTIARY_PHONE,
                            ).zip(phones).forEach { (key, number) -> putExtra(key, number) }
                        }
                    else -> null
                }
                if (intent == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Its own task: if the other app crashes, ours stays up.
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                result.success(try {
                    startActivity(intent); true
                } catch (e: ActivityNotFoundException) {
                    false
                })
            }
    }
}
