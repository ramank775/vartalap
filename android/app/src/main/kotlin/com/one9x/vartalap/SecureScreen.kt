package com.one9x.vartalap

import android.app.Activity
import android.app.KeyguardManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Decision 222, the `vartalap/secure` channel: a secure message opens only
 * after the phone's own screen lock (fingerprint, face, PIN, pattern or
 * password), and the screen cannot be captured while it shows. Framework
 * APIs only: no AndroidX Biometric, no Play services.
 */
object SecureScreen {
    private const val REQUEST = 4222
    private var pending: MethodChannel.Result? = null

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "lockSet" -> result.success(keyguard(activity).isDeviceSecure)
            "unlock" -> unlock(activity, call.arguments as String, result)
            "lockSettings" -> result.success(try {
                activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)); true
            } catch (e: ActivityNotFoundException) {
                false
            })
            "noCapture" -> {
                if (call.arguments == true) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun keyguard(context: Context) =
        context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

    /** true once the user got past the screen lock; false if they backed out. */
    private fun unlock(activity: Activity, title: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val builder = BiometricPrompt.Builder(activity).setTitle(title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                @Suppress("DEPRECATION")
                builder.setDeviceCredentialAllowed(true)
            }
            builder.build().authenticate(
                CancellationSignal(),
                activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult?) {
                        result.success(true)
                    }

                    // Cancelled, locked out or no lock: terminal. A finger
                    // that does not match is not; the prompt stays up.
                    override fun onAuthenticationError(code: Int, message: CharSequence?) {
                        result.success(false)
                    }
                }
            )
            return
        }
        // Android 7 to 9: the system's confirm-your-PIN screen.
        @Suppress("DEPRECATION")
        val intent = keyguard(activity).createConfirmDeviceCredentialIntent(title, null)
        if (intent == null) {
            result.success(false)
            return
        }
        pending?.success(false)
        pending = result
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST)
    }

    /** From MainActivity.onActivityResult; true when it was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        pending?.success(resultCode == Activity.RESULT_OK)
        pending = null
        return true
    }
}
