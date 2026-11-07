package com.one9x.vartalap

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

/**
 * The `vartalap/media` channel: a photo made ready to send, and a sent
 * video's thumbnail (SYNC_PROTOCOL §24.4). Framework APIs only, off the
 * main thread; null when the file will not decode (the app then sends the
 * photo as picked, the video without a thumbnail).
 */
object MediaPrep {
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")!!
        val out = call.argument<String>("out")!!
        val work: () -> Any? = when (call.method) {
            "photo" -> { ->
                photo(path, out, call.argument<Int>("maxSide")!!, call.argument<Int>("quality")!!)
            }
            "videoThumbnail" -> { -> videoThumbnail(path, out) }
            else -> {
                result.notImplemented()
                return
            }
        }
        Thread {
            val answer = try {
                work()
            } catch (e: Throwable) { // OutOfMemoryError too: a huge photo goes as picked
                null
            }
            main.post { result.success(answer) }
        }.start()
    }

    /**
     * [path] as a JPEG at most [maxSide] pixels on its long side, turned
     * upright, with no EXIF (so no location) left in it. [width, height].
     */
    private fun photo(path: String, out: String, maxSide: Int, quality: Int): List<Int>? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        val long = maxOf(bounds.outWidth, bounds.outHeight)
        if (long <= 0) return null
        // Decode at a power-of-two fraction that still covers about the
        // target, so a 50 MP photo never sits whole in memory.
        var sample = 1
        while (long / (sample * 2) >= maxSide * 3 / 4) sample *= 2
        val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sample
        }) ?: return null
        val matrix = Matrix()
        val scale = maxSide.toFloat() / maxOf(decoded.width, decoded.height)
        if (scale < 1f) matrix.postScale(scale, scale)
        when (ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
        )) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        }
        val ready = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        FileOutputStream(out).use { ready.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        return listOf(ready.width, ready.height)
    }

    /**
     * A small JPEG of [path]'s first frame, 320 pixels on its long side,
     * into [out]; the video's upright size and length.
     */
    private fun videoThumbnail(path: String, out: String): Map<String, Int>? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(0) ?: return null
            val scale = 320f / maxOf(frame.width, frame.height)
            val small = if (scale < 1f) Bitmap.createScaledBitmap(
                frame, (frame.width * scale).toInt(), (frame.height * scale).toInt(), true
            ) else frame
            FileOutputStream(out).use { small.compress(Bitmap.CompressFormat.JPEG, 60, it) }
            fun meta(key: Int) =
                retriever.extractMetadata(key)?.toIntOrNull() ?: 0
            val turned = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) % 180 != 0
            val w = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val h = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            return mapOf(
                "width" to if (turned) h else w,
                "height" to if (turned) w else h,
                "durationMs" to meta(MediaMetadataRetriever.METADATA_KEY_DURATION),
            )
        } finally {
            retriever.release()
        }
    }
}
