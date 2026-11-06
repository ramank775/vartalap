package com.one9x.vartalap

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.location.LocationListenerCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.location.LocationRequestCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.Date

/**
 * Live location (SYNC_PROTOCOL §21): a foreground service, type location,
 * with an ongoing notification and a Stop action, so sharing goes on with
 * the app closed. Positions come from the platform LocationManager (the
 * one-shot location's path), never Play services. Each one goes to a
 * Flutter engine of the service's own (`--live-location`), whose Dart
 * side (lib/services/live_location.dart) seals and sends it and says
 * what the notification shows; null there means nothing is shared any
 * more, and the service stops.
 *
 * Battery: the provider is asked for at most one fix a minute and only
 * after 50 m of movement (the platform's fused provider at balanced
 * power on Android 12+, GPS and network before), and while the phone
 * stays put one fix every 10 minutes tells the people watching that it
 * is still on.
 */
class LiveLocationService : Service(), LocationListenerCompat {
    companion object {
        private const val CHANNEL = "vartalap/live_location"
        private const val NOTIFICATION_CHANNEL = "live_location"
        private const val NOTIFICATION_ID = 7001
        private const val REFUSED_ID = 7002
        private const val ACTION_STOP = "com.one9x.vartalap.LIVE_LOCATION_STOP"
        private const val INTERVAL_MS = 60_000L
        private const val MIN_DISTANCE_M = 50f
        private const val STILL_MS = 10 * 60_000L

        /** One process: every engine reaches the running service here. */
        private var running: LiveLocationService? = null

        /** `vartalap/live_location` on each live engine, for "changed". */
        private val channels = mutableSetOf<MethodChannel>()

        /**
         * The channel on [engine]: the app's (MainActivity), a push wake's
         * (PushInbox) and the service's own. Main thread.
         */
        fun register(engine: FlutterEngine, context: Context): MethodChannel {
            val app = context.applicationContext
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(start(
                        app,
                        call.argument<Boolean>("background") == true,
                        call.argument<String>("refusedTitle"),
                        call.argument<String>("title")
                    ))
                    "changed" -> {
                        running?.sync()
                        channels.filter { it !== channel }.forEach { it.invokeMethod("changed", null) }
                        result.success(null)
                    }
                    "ready" -> {
                        running?.takeIf { it.dart === channel }?.onDartReady()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
            channels.add(channel)
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}
                override fun onEngineWillDestroy() {
                    channels.remove(channel)
                }
            })
            return channel
        }

        private fun granted(context: Context, permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        /**
         * Start the service, or have the running one re-read the shares.
         * [background]: a contact turned it on (a push wake), which needs
         * location "all the time". Android 12+ refuses a start from the
         * background unless the push was Google's high-priority one or the
         * app is left out of battery optimization; then, as for a missing
         * permission, [refusedTitle] goes up as a notification to open the
         * app. [title]: a contact's start, announced at once with a sound.
         */
        private fun start(
            context: Context,
            background: Boolean,
            refusedTitle: String?,
            title: String?
        ): String {
            val lm = context.getSystemService(LOCATION_SERVICE) as LocationManager
            val status = when {
                !granted(context, Manifest.permission.ACCESS_FINE_LOCATION) &&
                    !granted(context, Manifest.permission.ACCESS_COARSE_LOCATION) -> "permission"
                background && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    !granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) -> "permission"
                !LocationManagerCompat.isLocationEnabled(lm) -> "off"
                running != null -> {
                    running!!.announce(title)
                    running!!.sync()
                    "started"
                }
                else -> try {
                    ContextCompat.startForegroundService(
                        context,
                        Intent(context, LiveLocationService::class.java).putExtra("title", title)
                    )
                    "started"
                } catch (e: Exception) {
                    // ForegroundServiceStartNotAllowedException, Android 12+
                    "refused"
                }
            }
            if (status != "started" && refusedTitle != null) refusedNotice(context, refusedTitle)
            return status
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL, "Live location", NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "While your live location is shared." }
            )
        }

        private fun openApp(context: Context): PendingIntent? =
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
            }

        private fun refusedNotice(context: Context, title: String) {
            ensureChannel(context)
            context.getSystemService(NotificationManager::class.java).notify(
                REFUSED_ID,
                NotificationCompat.Builder(context, NOTIFICATION_CHANNEL)
                    .setSmallIcon(R.drawable.ic_stat_vartalap)
                    .setContentTitle(title)
                    .setContentText("Open Vartalap to share your live location.")
                    .setContentIntent(openApp(context))
                    .setAutoCancel(true)
                    .build()
            )
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var dart: MethodChannel? = null
    private var dartReady = false
    private var stopping = false

    /** A fix that came before the Dart side was up. */
    private var pending: Map<String, Any>? = null
    private var last: Location? = null
    private var lastSentAt = 0L

    private var title = "Sharing live location"
    private var text = ""
    private var until = 0L
    private var remote = false

    private val still = object : Runnable {
        override fun run() {
            if (SystemClock.elapsedRealtime() - lastSentAt >= STILL_MS - 1_000) currentFix()
            handler.postDelayed(this, STILL_MS)
        }
    }
    private val expiry = Runnable { sync() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAll()
            return START_NOT_STICKY
        }
        if (engine != null) {
            sync()
            return START_STICKY
        }
        intent?.getStringExtra("title")?.let {
            title = it
            remote = true
        }
        try {
            ensureChannel(this)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification())
            }
        } catch (e: Exception) {
            // No location access for a background start (Android 14+), or
            // a sticky restart Android 12+ will not allow: the app resumes
            // the shares when it next opens.
            stopSelf()
            return START_NOT_STICKY
        }
        startUpdates()
        engine = FlutterEngine(applicationContext).apply {
            localizationPlugin.sendLocalesToFlutter(resources.configuration)
            dart = register(this, this@LiveLocationService)
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(), listOf("--live-location")
            )
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopUpdates()
        engine?.destroy()
        engine = null
        dart = null
        running = null
        // The app's screens re-read what the service's engine changed.
        channels.forEach { it.invokeMethod("changed", null) }
        super.onDestroy()
    }

    private fun onDartReady() {
        dartReady = true
        if (stopping) {
            stopAll()
            return
        }
        val fix = pending
        pending = null
        if (fix != null) call("fix", fix) else sync()
    }

    private fun call(method: String, args: Any?) {
        val channel = dart ?: return
        if (!dartReady || stopping) return
        channel.invokeMethod(method, args, object : MethodChannel.Result {
            override fun success(result: Any?) = onStatus(result as? Map<*, *>)
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        })
    }

    fun sync() = call("sync", null)

    /** A contact turned it on while it already ran: say so, with a sound. */
    private fun announce(contactTitle: String?) {
        if (contactTitle == null || stopping) return
        title = contactTitle
        remote = true
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification(alertAgain = true))
    }

    /** What the Dart side says to show; null: nothing is shared, stop. */
    private fun onStatus(status: Map<*, *>?) {
        if (stopping) return
        if (status == null) {
            finish()
            return
        }
        title = status["title"] as? String ?: title
        text = status["text"] as? String ?: ""
        until = (status["until"] as? Number)?.toLong() ?: 0L
        remote = status["remote"] == true
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification())
        handler.removeCallbacks(expiry)
        handler.postDelayed(expiry, maxOf(1_000L, until - System.currentTimeMillis() + 1_000L))
    }

    private fun notification(alertAgain: Boolean = false) = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
        .setSmallIcon(R.drawable.ic_stat_vartalap)
        .setContentTitle(title)
        .setContentText(
            listOf(
                text,
                if (until > 0) "Until " + android.text.format.DateFormat.getTimeFormat(this).format(Date(until)) else ""
            ).filter { it.isNotEmpty() }.joinToString(" · ")
        )
        .setOngoing(true)
        .setOnlyAlertOnce(!alertAgain)
        // A contact turning it on alerts once; the user's own share does not.
        .setSilent(!remote)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setContentIntent(openApp(this))
        .addAction(
            0, "Stop",
            PendingIntent.getService(
                this, 0,
                Intent(this, LiveLocationService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE
            )
        )
        .build()

    /** The notification's Stop: the Dart side stops every share and sends the stops. */
    private fun stopAll() {
        stopping = true
        stopUpdates()
        stopForeground(STOP_FOREGROUND_REMOVE)
        val channel = dart
        if (channel == null) {
            stopSelf()
            return
        }
        // Not up yet: [onDartReady] comes back here.
        if (!dartReady) return
        handler.postDelayed({ stopSelf() }, 20_000)
        channel.invokeMethod("stopAll", null, object : MethodChannel.Result {
            override fun success(result: Any?) = stopSelf()
            override fun error(code: String, message: String?, details: Any?) = stopSelf()
            override fun notImplemented() = stopSelf()
        })
    }

    private fun finish() {
        stopping = true
        stopUpdates()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun providers(lm: LocationManager): List<String> =
        // "fused" here is the platform's own (Android 12+), not Play services'.
        if (lm.allProviders.contains("fused")) listOf("fused")
        else listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { lm.allProviders.contains(it) }

    private fun startUpdates() {
        val lm = getSystemService(LOCATION_SERVICE) as LocationManager
        val request = LocationRequestCompat.Builder(INTERVAL_MS)
            .setMinUpdateDistanceMeters(MIN_DISTANCE_M)
            .setQuality(LocationRequestCompat.QUALITY_BALANCED_POWER_ACCURACY)
            .build()
        providers(lm).forEach {
            try {
                LocationManagerCompat.requestLocationUpdates(
                    lm, it, request, ContextCompat.getMainExecutor(this), this
                )
            } catch (e: SecurityException) {
            } catch (e: IllegalArgumentException) {
            }
        }
        currentFix()
        handler.postDelayed(still, STILL_MS)
    }

    private fun stopUpdates() {
        handler.removeCallbacks(still)
        LocationManagerCompat.removeUpdates(getSystemService(LOCATION_SERVICE) as LocationManager, this)
    }

    /** One fix now: at the start, and while the phone stays put. */
    private fun currentFix() {
        val lm = getSystemService(LOCATION_SERVICE) as LocationManager
        val provider = providers(lm).reversed().firstOrNull { lm.isProviderEnabled(it) } ?: return
        try {
            LocationManagerCompat.getCurrentLocation(
                lm, provider, CancellationSignal(), ContextCompat.getMainExecutor(this)
            ) { it?.let { loc -> consider(loc, force = true) } }
        } catch (e: SecurityException) {
        }
    }

    override fun onLocationChanged(location: Location) = consider(location, force = false)

    private fun consider(loc: Location, force: Boolean) {
        if (stopping) return
        val prev = last
        // GPS and network both report (before Android 12): a fix within
        // 30 s of the last one sent goes only if it moved 50 m.
        if (!force && prev != null &&
            SystemClock.elapsedRealtime() - lastSentAt < 30_000 &&
            loc.distanceTo(prev) < MIN_DISTANCE_M
        ) return
        last = loc
        lastSentAt = SystemClock.elapsedRealtime()
        val fix = mapOf<String, Any>(
            "lat" to loc.latitude,
            "lng" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "at" to loc.time
        )
        if (dartReady) call("fix", fix) else pending = fix
    }
}
