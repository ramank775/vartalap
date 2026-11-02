package com.one9x.vartalap

import android.content.Context
import android.content.pm.PackageManager
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

/**
 * Google push (decision 209): Firebase Cloud Messaging. Only the gms build
 * has this; the foss one answers "not available".
 */
object GooglePush {
    /** Play services installed and enabled, and this build carries a Firebase config. */
    fun available(context: Context): Boolean = try {
        context.packageManager.getApplicationInfo("com.google.android.gms", 0).enabled &&
            FirebaseApp.getApps(context).isNotEmpty()
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /** This install's FCM registration token, or null when there is none to be had. */
    fun token(context: Context, done: (String?) -> Unit) {
        if (!available(context)) return done(null)
        FirebaseMessaging.getInstance().token.addOnCompleteListener {
            done(if (it.isSuccessful) it.result else null)
        }
    }
}
