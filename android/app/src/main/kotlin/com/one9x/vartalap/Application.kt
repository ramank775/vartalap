package com.one9x.vartalap

import io.flutter.app.FlutterApplication
import android.app.NotificationManager
import android.content.Context

class Application : FlutterApplication() {
    @Override
    override fun onCreate() {
        super.onCreate()
        cancelAllNotifications()
    }

    private fun cancelAllNotifications() {
        val notificationManager: NotificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
    }
}