package com.capitalwizard.android.services

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import android.net.Uri
import android.util.Base64
import androidx.core.content.IntentCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Private, durable handoff. URI grants are used while the receiving Activity lives. */
object SharedImageInbox {
    private const val MAX_BYTES = 10 * 1024 * 1024
    private const val MAX_FILES = 4
    private val idPattern = Regex("[0-9a-fA-F-]{36}")
    private fun directory(context: Context) = File(context.noBackupFilesDir, "shared-images").apply { mkdirs() }

    fun isShare(intent: Intent?): Boolean = intent?.action in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)

    /** Run off the UI thread. Reject the entire batch rather than silently dropping files. */
    @Synchronized
    fun capture(context: Context, intent: Intent) {
        require(intent.type?.startsWith("image/") == true)
        val streams = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        } else listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
        val uris = streams.ifEmpty {
            val clip = intent.clipData
            (0 until (clip?.itemCount ?: 0)).mapNotNull { clip?.getItemAt(it)?.uri }
        }.distinct()
        require(uris.size in 1..MAX_FILES)
        val folder = directory(context)
        require(pendingFiles(folder).size < 10)
        val files = JSONArray()
        var totalBytes = 0
        uris.forEachIndexed { index, uri ->
            // Only external content grants, never a file:// path into our own sandbox.
            require(uri.scheme == "content")
            val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= MAX_BYTES)
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: error("unreadable")
            require(bytes.isNotEmpty())
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            require(bounds.outWidth > 0 && bounds.outHeight > 0)
            var mime = bounds.outMimeType ?: ""
            var image = bytes
            if (mime !in listOf("image/jpeg", "image/png", "image/webp", "image/gif")) {
                // HEIC/HEIF are common camera shares but are not accepted by chat models.
                val options = BitmapFactory.Options()
                while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > 2560) options.inSampleSize *= 2
                val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: error("unsupported")
                val orientation = ByteArrayInputStream(bytes).use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1) }
                val matrix = Matrix().apply {
                    when (orientation) {
                        2 -> setScale(-1f, 1f)
                        3 -> setRotate(180f)
                        4 -> setScale(1f, -1f)
                        5 -> { setRotate(90f); postScale(-1f, 1f) }
                        6 -> setRotate(90f)
                        7 -> { setRotate(-90f); postScale(-1f, 1f) }
                        8 -> setRotate(-90f)
                    }
                }
                val bitmap = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                if (bitmap !== decoded) decoded.recycle()
                image = ByteArrayOutputStream().use { output ->
                    try { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)); output.toByteArray() }
                    finally { bitmap.recycle() }
                }
                mime = "image/jpeg"
            }
            totalBytes += image.size
            require(totalBytes <= MAX_BYTES)
            val extension = when (mime) { "image/png" -> "png"; "image/webp" -> "webp"; "image/gif" -> "gif"; else -> "jpg" }
            files.put(JSONObject().put("name", "shared-image-${index + 1}.$extension")
                .put("mime", mime).put("base64", Base64.encodeToString(image, Base64.NO_WRAP)))
        }
        val id = UUID.randomUUID().toString()
        val payload = JSONObject().put("id", id).put("files", files)
            .put("text", intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.take(4000) ?: "")
        val temporary = File(folder, "$id.tmp")
        temporary.writeText(payload.toString())
        check(temporary.renameTo(File(folder, "$id.json")))
    }

    private fun pendingFiles(folder: File): List<File> {
        val cutoff = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        return folder.listFiles().orEmpty().filter { file ->
            if (file.lastModified() < cutoff) { file.delete(); false }
            else file.extension == "json"
        }.sortedBy { it.lastModified() }
    }

    @Synchronized fun next(context: Context): String? = pendingFiles(directory(context)).firstOrNull()?.readText()
    @Synchronized fun acknowledge(context: Context, id: String) {
        if (idPattern.matches(id)) File(directory(context), "$id.json").delete()
    }
}
