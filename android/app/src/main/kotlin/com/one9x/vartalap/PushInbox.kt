package com.one9x.vartalap

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.unifiedpush.flutter.connector.Plugin
import org.unifiedpush.flutter.connector.UnifiedPushService

/**
 * Where a push wake (FCM or a UnifiedPush app) is delivered: the push
 * plugin's inbox (`Plugin.calls`) of an engine that is alive.
 *
 * The plugin (unifiedpush_android 3.4.0) keeps only the inbox of the engine
 * that registered it last, and every engine registers it, a WorkManager
 * job's too. WorkManager destroys that engine when the job ends, so every
 * wake after the hourly message check went to an inbox nobody read, until
 * the process died. Instead: the app's own engine while it is up, else one
 * wake engine of ours, started once and kept.
 */
object PushInbox {
    /** MainActivity's engine, while it lives. */
    @Volatile
    var app: FlutterEngine? = null
    private var wake: FlutterEngine? = null

    /** Point `Plugin.calls` at a live engine's inbox. Main thread only. */
    fun point(context: Context) {
        val engine = app ?: wake ?: FlutterEngine(context.applicationContext).apply {
            localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                listOf("--unifiedpush-bg")
            )
        }.also { wake = it }
        Plugin.calls = (engine.plugins.get(Plugin::class.java) as Plugin).calls
    }
}

/**
 * The plugin's service for UnifiedPush apps (foss builds), re-pointing the
 * inbox before each event it forwards (see [PushInbox]). Replaces the
 * plugin's own in AndroidManifest.xml.
 */
class WakePushService : UnifiedPushService() {
    override fun onCreate() {
        PushInbox.point(this)
        super.onCreate()
    }

    private fun pointed(forward: () -> Unit) {
        Handler(Looper.getMainLooper()).post {
            PushInbox.point(this)
            forward()
        }
    }

    override fun onMessage(message: PushMessage, instance: String) =
        pointed { super.onMessage(message, instance) }

    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) =
        pointed { super.onNewEndpoint(endpoint, instance) }

    override fun onRegistrationFailed(reason: FailedReason, instance: String) =
        pointed { super.onRegistrationFailed(reason, instance) }

    override fun onUnregistered(instance: String) =
        pointed { super.onUnregistered(instance) }

    override fun onTempUnavailable(instance: String) =
        pointed { super.onTempUnavailable(instance) }
}
