package com.example.human_twin_ai

import android.app.PendingIntent
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Shares exported files through this app's own FileProvider (avoids manifest conflicts with plugins). */
class HumanTwinFileProvider : FileProvider()

/**
 * Device services for the local v1 (no permissions): app-private storage paths, the Android
 * share sheet, "save as" via the Storage Access Framework, and gallery saves via MediaStore
 * on Android 10+. Everything here works on files the app already wrote; nothing is uploaded.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var pendingShare: MethodChannel.Result? = null
    private var shareLaunched = false
    private var pendingSave: PendingSave? = null
    private val finishShareRunnable = Runnable { finishShare() }

    private data class PendingSave(val source: File, val result: MethodChannel.Result)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "paths" -> result.success(
                mapOf(
                    // Not covered by Auto Backup or device transfer: photos and models stay on this phone.
                    "documents" to noBackupFilesDir.absolutePath,
                    "cache" to cacheDir.absolutePath,
                    "sdkInt" to Build.VERSION.SDK_INT,
                ),
            )
            "shareFile" -> shareFile(
                File(call.argument<String>("path")!!),
                call.argument<String>("mimeType")!!,
                result,
            )
            "saveDocument" -> saveDocument(
                File(call.argument<String>("path")!!),
                call.argument<String>("fileName")!!,
                call.argument<String>("mimeType")!!,
                result,
            )
            "saveImageToGallery" -> saveImageToGallery(
                File(call.argument<String>("path")!!),
                call.argument<String>("fileName")!!,
                result,
            )
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- share

    private fun shareFile(file: File, mimeType: String, result: MethodChannel.Result) {
        if (pendingShare != null || pendingSave != null) {
            result.error("busy", "Another share or save is in progress", null)
            return
        }
        try {
            val uri: Uri = FileProvider.getUriForFile(this, "$packageName.humantwin.files", file)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val callback = Intent(this, ShareTargetReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val sender = PendingIntent.getBroadcast(this, SHARE_REQUEST, callback, flags).intentSender
            ShareTargetReceiver.chosen = null
            pendingShare = result
            shareLaunched = true
            startActivity(Intent.createChooser(send, null, sender))
        } catch (error: Exception) {
            pendingShare = null
            shareLaunched = false
            result.success(mapOf("status" to "failed"))
        }
    }

    override fun onResume() {
        super.onResume()
        if (pendingShare != null && shareLaunched) {
            // The chooser has no dismissal callback: report the chosen app if Android told us,
            // otherwise only that the sheet was closed (never that nothing was sent).
            main.removeCallbacks(finishShareRunnable)
            main.postDelayed(finishShareRunnable, 600)
        }
    }

    private fun finishShare() {
        val result = pendingShare ?: return
        pendingShare = null
        shareLaunched = false
        val component: ComponentName? = ShareTargetReceiver.chosen
        ShareTargetReceiver.chosen = null
        if (component == null) {
            result.success(mapOf("status" to "closed"))
            return
        }
        val label = try {
            val info = packageManager.getApplicationInfo(component.packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (error: Exception) {
            null
        }
        result.success(mapOf("status" to "handedOff", "app" to label))
    }

    // ------------------------------------------------------------ save as

    private fun saveDocument(source: File, fileName: String, mimeType: String, result: MethodChannel.Result) {
        if (pendingShare != null || pendingSave != null) {
            result.error("busy", "Another share or save is in progress", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        pendingSave = PendingSave(source, result)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, SAVE_REQUEST)
        } catch (error: Exception) {
            pendingSave = null
            result.success(mapOf("status" to "failed"))
        }
    }

    @Deprecated("Activity result API is not available on FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val target = data?.data
        val pending = pendingSave
        if (pending == null) {
            // The activity was recreated while the picker was open, so the bytes can no longer
            // be written: remove the empty document the picker created (never a non-empty one).
            if (resultCode == RESULT_OK && target != null) {
                io.execute { deleteIfEmpty(target) }
            }
            return
        }
        pendingSave = null
        if (resultCode != RESULT_OK || target == null) {
            pending.result.success(mapOf("status" to "cancelled"))
            return
        }
        io.execute {
            val ok = try {
                // Open the source first: an expired export must not truncate the destination.
                pending.source.inputStream().use { input ->
                    openForOverwrite(target)?.use { out -> input.copyTo(out) } != null
                }
            } catch (error: Exception) {
                false
            }
            if (!ok) {
                // Remove only a confirmed empty document. Never delete non-empty existing
                // content or a partial write; the user can inspect it after the reported failure.
                deleteIfEmpty(target)
            }
            main.post { pending.result.success(mapOf("status" to if (ok) "saved" else "failed")) }
        }
    }

    /** Refuse providers without truncating mode: "w" may leave an older file's tail. */
    private fun openForOverwrite(target: Uri) =
        contentResolver.openOutputStream(target, "wt")

    private fun deleteIfEmpty(target: Uri) {
        try {
            val size = contentResolver.query(
                target,
                arrayOf(DocumentsContract.Document.COLUMN_SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else -1L
            } ?: -1L
            if (size == 0L) {
                DocumentsContract.deleteDocument(contentResolver, target)
            }
        } catch (error: Exception) {
            // Best effort: the provider may not report a size or support deletion.
        }
    }

    // ------------------------------------------------------- gallery (29+)

    private fun saveImageToGallery(source: File, fileName: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Below Android 10 this would need a storage permission; the app uses "save as" instead.
            result.success(mapOf("status" to "unsupported"))
            return
        }
        io.execute {
            val location = "${Environment.DIRECTORY_PICTURES}/HumanTwin"
            val status = try {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, location)
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val uri = contentResolver.insert(collection, values)
                    ?: throw IllegalStateException("insert failed")
                try {
                    contentResolver.openOutputStream(uri, "w")!!.use { out ->
                        source.inputStream().use { input -> input.copyTo(out) }
                    }
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    "saved"
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    "failed"
                }
            } catch (error: Exception) {
                "failed"
            }
            main.post { result.success(mapOf("status" to status, "location" to "相册 · HumanTwin")) }
        }
    }

    override fun onDestroy() {
        main.removeCallbacks(finishShareRunnable)
        pendingShare?.success(mapOf("status" to "closed"))
        pendingShare = null
        pendingSave?.result?.success(mapOf("status" to "cancelled"))
        pendingSave = null
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "humantwin/device"
        private const val SAVE_REQUEST = 7301
        private const val SHARE_REQUEST = 7302
    }
}
