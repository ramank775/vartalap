package com.one9x.vartalap

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/**
 * Where Android's share sheet lands (photos, videos, documents, text from
 * another app). Started from that app, an activity joins that app's task,
 * so a MainActivity there would be a second copy of the whole app, with
 * its own Flutter engine, store and socket. This hands the share, read
 * grant included, to the one MainActivity in our own task, and goes.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(intent).setClass(this, MainActivity::class.java).setFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        )
        finish()
    }
}

/**
 * The `vartalap/share` channel (lib/screens/chat/share_to.dart): MainActivity
 * keeps the last share it was handed; Dart's `take` copies its files into
 * our cache (the read grant lasts only while the activity does) and gets
 * the paths, the shared text and what was left out.
 */
object SharedFiles {
    private val main = Handler(Looper.getMainLooper())
    private var pending: Intent? = null

    /**
     * A new MainActivity: no Dart from before is still using older copies.
     * [intent] is what started it; not one replayed from Recents.
     */
    fun start(context: Context, intent: Intent?) {
        File(context.cacheDir, "share").deleteRecursively()
        if (intent != null && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) {
            offer(intent)
        }
    }

    /** Keeps [intent] if it is a share; true if it was. */
    fun offer(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return false
        }
        pending = intent
        return true
    }

    fun take(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val intent = pending ?: return result.success(null)
        pending = null
        val maxBytes = call.argument<Number>("maxBytes")!!.toLong()
        val maxFiles = call.argument<Int>("maxFiles")!!
        Thread {
            val answer = copy(context.applicationContext, intent, maxBytes, maxFiles)
            main.post { result.success(answer) }
        }.start()
    }

    private fun copy(context: Context, intent: Intent, maxBytes: Long, maxFiles: Int): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val uris: List<Uri> = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty().filterNotNull()
        } else {
            listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        }
        val resolver = context.contentResolver
        val dir = File(context.cacheDir, "share/${System.nanoTime()}")
        val files = mutableListOf<String>()
        val tooBig = mutableListOf<String>()
        var unreadable = 0
        uris.take(maxFiles).forEachIndexed { i, uri ->
            try {
                // Only another app's content: a crafted file:// or link to
                // our own provider would have us send our own files away.
                require(
                    uri.scheme == ContentResolver.SCHEME_CONTENT &&
                        uri.authority?.startsWith(context.packageName) != true
                )
                val mime = resolver.getType(uri) ?: intent.type
                val name = withExtension(safeName(displayName(resolver, uri) ?: uri.lastPathSegment), mime)
                // Its own folder: the name is what the other side sees.
                val out = File(dir, "$i/$name").apply { parentFile!!.mkdirs() }
                // A photo is made smaller before it is sent; the rest
                // goes as it is, so it stops at the upload limit.
                val limit = if (mime?.startsWith("image/") == true) Long.MAX_VALUE else maxBytes
                val copied = resolver.openInputStream(uri)!!.use { input ->
                    out.outputStream().use { copyAtMost(input, it, limit) }
                }
                if (copied > limit) {
                    out.delete()
                    tooBig += name
                } else {
                    files += out.path
                }
            } catch (e: Exception) { // no grant, gone, not ours to read
                unreadable++
            }
        }
        return mapOf(
            "dir" to dir.path,
            "files" to files,
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "tooBig" to tooBig,
            "tooMany" to maxOf(0, uris.size - maxFiles),
            "unreadable" to unreadable,
        )
    }

    private fun displayName(resolver: ContentResolver, uri: Uri): String? =
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    /** A bare basename: it cannot climb out of the folder it is written to. */
    private fun safeName(name: String?): String {
        val base = name.orEmpty().substringAfterLast('/').substringAfterLast('\\').trim()
        return if (base.isEmpty() || base == "." || base == "..") "file" else base
    }

    /** The app tells a file's type by its extension: add one if missing. */
    private fun withExtension(name: String, mime: String?): String {
        if (name.contains('.')) return name
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: return name
        return "$name.$ext"
    }

    /** Copies up to [limit] bytes; more than [limit] = it did not fit. */
    private fun copyAtMost(input: InputStream, out: OutputStream, limit: Long): Long {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val n = input.read(buffer)
            if (n < 0) return total
            total += n
            if (total > limit) return total
            out.write(buffer, 0, n)
        }
    }
}
