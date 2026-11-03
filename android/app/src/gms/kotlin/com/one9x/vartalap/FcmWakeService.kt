package com.one9x.vartalap

import android.os.Handler
import android.util.Log
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.unifiedpush.flutter.connector.Call
import org.unifiedpush.flutter.connector.PLUGIN_ARG_INSTANCE
import org.unifiedpush.flutter.connector.PLUGIN_ARG_MESSAGE_CONTENT
import org.unifiedpush.flutter.connector.PLUGIN_ARG_MESSAGE_DECRYPTED
import org.unifiedpush.flutter.connector.PLUGIN_CALL_MESSAGE
import org.unifiedpush.flutter.connector.Plugin

/**
 * Decision 209: an FCM wake takes the path a UnifiedPush message does
 * (the plugin's UnifiedPushService.onMessage), so the Dart side has one
 * wake handler: start the background engine if the app is not running,
 * then hand the plugin a message. The wake carries nothing else.
 */
class FcmWakeService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        // Priority 2 sent as 1: Google downgraded our high-priority wakes,
        // which it does to apps whose wakes end without a notification
        // (decision 212). `adb logcat -s VartalapPush` shows it.
        Log.i("VartalapPush", "wake: priority ${message.priority} sent as " +
            "${message.originalPriority}, ${System.currentTimeMillis() - message.sentTime} ms after send")
        Handler(Looper.getMainLooper()).post {
            PushInbox.ensureReader(applicationContext)
            Plugin.calls.tryEmit(
                Call(
                    PLUGIN_CALL_MESSAGE,
                    mapOf(
                        PLUGIN_ARG_INSTANCE to "default",
                        PLUGIN_ARG_MESSAGE_CONTENT to ByteArray(0),
                        PLUGIN_ARG_MESSAGE_DECRYPTED to true
                    )
                )
            )
        }
        // ponytail: keeps this service, and so the process, alive while the
        // Dart wake pulls (5 s budget) and posts notifications, so Android
        // does not freeze it halfway. A done-signal from Dart would be exact.
        Thread.sleep(9_000)
    }

    // ponytail: a rotated token is posted on the next app start
    // (PushService.refresh); until then the server's push gets 404 and
    // drops the old one. Post it from here if that gap shows.
    override fun onNewToken(token: String) {}
}
