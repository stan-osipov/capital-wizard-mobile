package com.capitalwizard.android.services

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import androidx.core.content.IntentCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * Private, durable handoff. URI grants are used while the receiving Activity lives.
 *
 * Carries BOTH kinds of share, which is why `kind` is on the payload:
 *
 *   IMAGES    — up to 4 pictures. Opens an AI chat draft.
 *   STATEMENT — one document (PDF/XLS/CSV/…). Opens the import wizard.
 *
 * The object name and the folder still say "images" to stay in step with the
 * iOS twin, whose app group is provisioned under that name and cannot be
 * renamed without breaking the handoff mid-upgrade.
 *
 * Unlike iOS, both routes arrive the same way here: `LoginActivity` is the
 * share target for each (see src/capitalWizard/AndroidManifest.xml), so a share
 * always LAUNCHES the app. iOS needs two separate doors because a Share
 * Extension cannot launch its containing app.
 */
object SharedImageInbox {
    private const val MAX_BYTES = 10 * 1024 * 1024
    private const val MAX_FILES = 4
    private val idPattern = Regex("[0-9a-fA-F-]{36}")
    private fun directory(context: Context) = File(context.noBackupFilesDir, "shared-images").apply { mkdirs() }

    /** Where the web app routes a payload. Written into the JSON as `kind` and
     *  read by nativeSharedStatement.ts; an absent value there means IMAGES,
     *  which is what builds before documents existed wrote. */
    enum class Kind(val wire: String) { IMAGES("images"), STATEMENT("statement") }

    /** Pictures by NAME, for the common case of a file manager reporting
     *  `application/octet-stream` for everything it shares. */
    private val IMAGE_EXTENSIONS =
        setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff", "avif")

    fun isShare(intent: Intent?): Boolean = intent?.action in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)

    /** Which failure to report, decided without touching the resolver — it is
     *  only choosing the wording of a toast. */
    fun looksLikeImageShare(intent: Intent?): Boolean = intent?.type?.startsWith("image/") == true

    /** Run off the UI thread. Reject the entire batch rather than silently dropping files. */
    @Synchronized
    fun capture(context: Context, intent: Intent) {
        val uris = sharedUris(intent)
        require(uris.size in 1..MAX_FILES)
        if (looksLikeImageShare(intent)) {
            captureImages(context, intent, uris)
            return
        }
        // A statement is one file: the wizard parses one, and importing part of
        // a batch would be worse than refusing it.
        require(uris.size == 1)
        val uri = uris.first()
        val name = sanitizedName(displayName(context, uri))
        // `image/*` is not the only way a picture arrives — plenty of file
        // managers share everything as `application/octet-stream`. A picture
        // belongs in the AI chat whichever MIME type announced it.
        if (name != null && name.substringAfterLast('.', "").lowercase() in IMAGE_EXTENSIONS) {
            captureImages(context, intent, uris)
            return
        }
        captureStatement(context, uri, name)
    }

    private fun sharedUris(intent: Intent): List<Uri> {
        val streams = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        } else listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
        return streams.ifEmpty {
            val clip = intent.clipData
            (0 until (clip?.itemCount ?: 0)).mapNotNull { clip?.getItemAt(it)?.uri }
        }.distinct()
    }

    /**
     * The statement, carried through as the bytes the user shared.
     *
     * Nothing here judges whether the format is importable: the share sheet is
     * not the place to refuse a `.numbers` export, and the institution picker
     * the user is about to see is what finally decides. The only limit is the
     * one the transport imposes — the payload crosses into the WebView as
     * base64 inside an `evaluateJavascript` string.
     */
    private fun captureStatement(context: Context, uri: Uri, name: String?) {
        // Only external content grants, never a file:// path into our own sandbox.
        require(uri.scheme == "content")
        val folder = directory(context)
        require(pendingFiles(folder).size < 10)
        val bytes = readBounded(context, uri)
        val mime = context.contentResolver.getType(uri)?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        val files = JSONArray().put(
            JSONObject()
                // The web side reads this for the extension it routes on, so a
                // provider that reports no name at all still gets something
                // stable rather than an empty string.
                .put("name", name ?: "statement")
                .put("mime", mime)
                .put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP)),
        )
        write(folder, files, "", Kind.STATEMENT)
    }

    private fun captureImages(context: Context, intent: Intent, uris: List<Uri>) {
        val folder = directory(context)
        require(pendingFiles(folder).size < 10)
        val files = JSONArray()
        var totalBytes = 0
        uris.forEachIndexed { index, uri ->
            // Only external content grants, never a file:// path into our own sandbox.
            require(uri.scheme == "content")
            val bytes = readBounded(context, uri)
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
        write(folder, files, intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.take(4000) ?: "", Kind.IMAGES)
    }

    /** Streams the grant, refusing the moment it passes the cap rather than
     *  after a 2 GB video is already in memory. */
    private fun readBounded(context: Context, uri: Uri): ByteArray {
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
        return bytes
    }

    private fun displayName(context: Context, uri: Uri): String? =
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0) cursor.getString(column) else null
            }

    /** A basename, because the name is used as a file name and read for its
     *  extension on the other side. */
    private fun sanitizedName(raw: String?): String? {
        val name = raw?.substringAfterLast('/')?.substringAfterLast('\\')?.trim().orEmpty()
        if (name.isEmpty() || name == "." || name == "..") return null
        return name.take(200)
    }

    private fun write(folder: File, files: JSONArray, text: String, kind: Kind) {
        val id = UUID.randomUUID().toString()
        val payload = JSONObject().put("id", id).put("kind", kind.wire).put("files", files).put("text", text)
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
