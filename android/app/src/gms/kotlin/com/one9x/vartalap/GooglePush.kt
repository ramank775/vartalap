package com.one9x.vartalap

import android.content.Context
import android.content.pm.PackageManager

/**
 * Whether the embedded FCM distributor can work on this phone: Play
 * services installed and enabled. Only the gms build has this check.
 */
object GooglePush {
    fun available(context: Context): Boolean = try {
        context.packageManager.getApplicationInfo("com.google.android.gms", 0).enabled
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
