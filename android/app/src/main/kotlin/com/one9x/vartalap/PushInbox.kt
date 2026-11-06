package com.one9x.vartalap

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.flutter.connector.Plugin
import org.unifiedpush.flutter.connector.UnifiedPushService

/**
 * Every push event (FCM or a UnifiedPush app) goes into the push plugin's
 * one inbox, `Plugin.calls`, read by the engine whose Dart side
 * initialized the plugin last (unifiedpush_android 3.5.0). Once that
 * engine is gone (the app's, after its activity finishes) nobody reads it,
 * and the plugin starts a new engine only for the first event of a
 * process. So before each event: if nobody reads the inbox, start our wake
 * engine; the inbox replays what it holds once that engine initializes.
 *
 * A WorkManager job's engine never initializes push (`initializeApp`
 * `pushEvents: false`), so it never takes the inbox.
 */
object PushInbox {
    private var wake: FlutterEngine? = null
    private var wakeStartedAt = 0L

    /** Main thread only. */
    fun ensureReader(context: Context) {
        if (Plugin.calls.subscriptionCount.value > 0) return
        val now = SystemClock.elapsedRealtime()
        // ponytail: a wake engine still starting reads nothing yet; 30 s for
        // its Dart side to initialize before it counts as gone.
        if (wake != null && now - wakeStartedAt < 30_000) return
        // An earlier wake engine that lost the inbox to the app's engine,
        // since gone: it reads nothing and never will again.
        wake?.destroy()
        wake = FlutterEngine(context.applicationContext).apply {
            localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
            // A contact's "turn on my live location" arrives on a wake.
            LiveLocationService.register(this, context)
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                listOf("--unifiedpush-bg")
            )
        }
        wakeStartedAt = now
    }
}

/**
 * The plugin's service for UnifiedPush apps (foss builds), making sure the
 * inbox has a reader before each event it forwards (see [PushInbox]).
 * Replaces the plugin's own in AndroidManifest.xml.
 */
class WakePushService : UnifiedPushService() {
    override fun onCreate() {
        PushInbox.ensureReader(this)
        super.onCreate()
    }

    private fun withReader(forward: () -> Unit) {
        Handler(Looper.getMainLooper()).post {
            PushInbox.ensureReader(this)
            forward()
        }
    }

    override fun onMessage(message: PushMessage, instance: String) =
        withReader { super.onMessage(message, instance) }

    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) =
        withReader { super.onNewEndpoint(endpoint, instance) }

    override fun onRegistrationFailed(reason: FailedReason, instance: String) =
        withReader { super.onRegistrationFailed(reason, instance) }

    override fun onUnregistered(instance: String) =
        withReader { super.onUnregistered(instance) }

    override fun onTempUnavailable(instance: String) =
        withReader { super.onTempUnavailable(instance) }
}
