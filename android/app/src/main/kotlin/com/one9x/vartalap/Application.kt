package com.one9x.vartalap

import io.flutter.app.FlutterApplication
import androidx.core.content.pm.PackageInfoCompat
import java.io.File

class Application : FlutterApplication() {
    @Override
    override fun onCreate() {
        super.onCreate()
        recordCrashes()
        // Notifications are not cleared here: a chat's stays until it is
        // read, and a push wake or a notification's Reply starts the process.
    }

    /**
     * A crash of any thread in this process leaves its exception types and
     * frames (never their messages, which can hold user data) in
     * files/crash_reports, as `<ms>.android.txt`: the build, then the trace.
     * The app offers it on its next start (lib/services/crash_reports.dart).
     * ponytail: JVM exceptions only; a native (engine) crash or an ANR leaves
     * nothing. ApplicationExitInfo (Android 11+) has both, if they show up in
     * Play vitals.
     */
    private fun recordCrashes() {
        val build = try {
            val info = packageManager.getPackageInfo(packageName, 0)
            "${info.versionName}+${PackageInfoCompat.getLongVersionCode(info)}"
        } catch (e: Exception) {
            ""
        }
        val dir = File(filesDir, "crash_reports")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val trace = StringBuilder(build).append('\n')
                var cause: Throwable? = error
                var depth = 0
                while (cause != null && depth++ < 10) {
                    if (depth > 1) trace.append("Caused by: ")
                    trace.append(cause.javaClass.name).append('\n')
                    cause.stackTrace.take(60).forEach { trace.append("\tat ").append(it).append('\n') }
                    cause = cause.cause
                }
                dir.mkdirs()
                // a crash loop must not fill the phone
                if ((dir.list()?.size ?: 0) < 10) {
                    File(dir, "${System.currentTimeMillis()}.android.txt").writeText(trace.toString())
                }
            } catch (ignored: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }
}
