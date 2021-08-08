package com.one9x.vartalap;

import io.flutter.app.FlutterApplication;
import android.app.NotificationManager;
import android.content.Context;

public class Application extends FlutterApplication {
  @Override
  public void onCreate() {
    super.onCreate();
    cancelAllNotifications();
  }

  private void cancelAllNotifications() {
    NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    notificationManager.cancelAll();
  }
}