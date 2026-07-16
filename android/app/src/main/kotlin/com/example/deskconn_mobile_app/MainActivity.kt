package com.example.deskconn_mobile_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.util.Patterns
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val shellChannel = "deskconn/shell_notification"
    private val notifChannel = "deskconn/notification"
    private val fileChannel = "deskconn/file"
    private val shareChannel = "deskconn/share"
    private val channelId = "deskconn_session_v2"
    private val notifId = 1107
    private var pendingSharedFiles: List<Map<String, Any?>> = emptyList()
    // True only when this Activity instance was freshly created (cold start)
    // specifically to handle an incoming share. If the app was already
    // running and received the share via onNewIntent instead, this stays
    // false so we never finish() an Activity the user is actively using.
    private var launchedForShareOnly = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
        pendingSharedFiles = extractSharedFiles(intent)
        launchedForShareOnly = pendingSharedFiles.isNotEmpty()
    }

    // Flutter's default behavior for back-with-nothing-left-to-pop is to
    // finish() the Activity, which destroys this FlutterEngine and every live
    // WAMP/WebRTC connection along with it.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val sharedFiles = extractSharedFiles(intent)
        if (sharedFiles.isNotEmpty()) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, shareChannel).invokeMethod("sharedFiles", sharedFiles)
            }
            return
        }

        val realm = intent.getStringExtra("realm") ?: return
        val method = when (intent.action) {
            "deskconn.OPEN_Terminal" -> "openTerminal"
            "deskconn.CLOSE_Terminal" -> "closeTerminal"
            else -> return
        }
        flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, shellChannel).invokeMethod(method, mapOf("realm" to realm))
        }
    }

    override fun onDestroy() {
        if (isFinishing) {
            getSharedPreferences("id.flutter.background_service", Context.MODE_PRIVATE)
                .edit().putBoolean("is_manually_stopped", true).apply()
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notifChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> { showNotification(); result.success(null) }
                    "hide" -> { hideNotification(); result.success(null) }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val filename = call.argument<String>("filename") ?: run {
                            result.error("INVALID_ARGS", "filename required", null); return@setMethodCallHandler
                        }
                        val bytes = call.argument<ByteArray>("bytes") ?: run {
                            result.error("INVALID_ARGS", "bytes required", null); return@setMethodCallHandler
                        }
                        try {
                            val path = saveToDownloads(filename, bytes)
                            result.success(path)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeInitialSharedFiles" -> {
                        val files = pendingSharedFiles
                        pendingSharedFiles = emptyList()
                        result.success(files)
                    }
                    "finishIfShareOnly" -> {
                        if (launchedForShareOnly) {
                            finishAndRemoveTask()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun extractSharedFiles(intent: Intent?): List<Map<String, Any?>> {
        if (intent == null) return emptyList()
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                readStreamUri(intent)?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val streams = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (streams != null) uris.addAll(streams)
            }
            else -> return emptyList()
        }

        if (uris.isEmpty()) {
            intent.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i).uri?.let { uris.add(it) }
                }
            }
        }

        if (uris.isEmpty() && intent.action == Intent.ACTION_SEND) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (!text.isNullOrEmpty()) {
                return copySharedTextToCache(text)?.let { listOf(it) } ?: emptyList()
            }
        }

        return uris.mapNotNull { copySharedUriToCache(it, intent.type) }
    }

    private fun copySharedTextToCache(text: String): Map<String, Any?>? {
        return try {
            val dir = File(cacheDir, "shared")
            dir.mkdirs()
            val baseName = if (Patterns.WEB_URL.matcher(text).matches()) "shared-link" else "shared-text"
            var target = File(dir, "$baseName.txt")
            var n = 1
            while (target.exists()) {
                target = File(dir, "$baseName ($n).txt")
                n++
            }
            target.writeText(text)
            mapOf(
                "path" to target.absolutePath,
                "name" to target.name,
                "mimeType" to "text/plain",
                "size" to target.length()
            )
        } catch (e: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun readStreamUri(intent: Intent): Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)

    private fun copySharedUriToCache(uri: Uri, mimeType: String?): Map<String, Any?>? {
        return try {
            val (displayName, declaredSize) = querySharedFileInfo(uri)
            val safeName = sanitizeFilename(displayName ?: "shared-file")
            val dir = File(cacheDir, "shared")
            dir.mkdirs()
            var target = File(dir, safeName)
            if (target.exists()) {
                val dot = safeName.lastIndexOf('.')
                val stem = if (dot > 0) safeName.substring(0, dot) else safeName
                val ext = if (dot > 0) safeName.substring(dot) else ""
                var n = 1
                while (target.exists()) {
                    target = File(dir, "$stem ($n)$ext")
                    n++
                }
            }

            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null

            mapOf(
                "path" to target.absolutePath,
                "name" to target.name,
                "mimeType" to mimeType,
                "size" to if (declaredSize >= 0) declaredSize else target.length()
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun querySharedFileInfo(uri: Uri): Pair<String?, Long> {
        if (uri.scheme == "file") {
            val file = File(uri.path ?: return Pair(null, -1))
            return Pair(file.name, file.length())
        }

        var name: String? = null
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) name = cursor.getString(nameIndex)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
            }
        }
        return Pair(name, size)
    }

    private fun sanitizeFilename(name: String): String {
        val cleaned = name.replace(Regex("""[\\/:*?"<>|]"""), "_").trim()
        return cleaned.ifEmpty { "shared-file" }
    }

    private fun saveToDownloads(filename: String, bytes: ByteArray): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val mime = getMimeType(filename)
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("MediaStore insert failed")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("Failed to open output stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            "Downloads/$filename"
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.mkdirs()
            var target = File(dir, filename)
            if (target.exists()) {
                val dot = filename.lastIndexOf('.')
                val stem = if (dot > 0) filename.substring(0, dot) else filename
                val ext = if (dot > 0) filename.substring(dot) else ""
                var n = 1
                while (target.exists()) { target = File(dir, "$stem ($n)$ext"); n++ }
            }
            target.writeBytes(bytes)
            target.absolutePath
        }
    }

    private fun getMimeType(filename: String): String = when (filename.substringAfterLast('.', "").lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "svg" -> "image/svg+xml"
        "pdf" -> "application/pdf"
        "mp4", "m4v" -> "video/mp4"
        "mkv" -> "video/x-matroska"
        "mov" -> "video/quicktime"
        "avi" -> "video/x-msvideo"
        "mp3" -> "audio/mpeg"
        "wav" -> "audio/wav"
        "ogg" -> "audio/ogg"
        "flac" -> "audio/flac"
        "aac", "m4a" -> "audio/aac"
        "txt", "md", "log" -> "text/plain"
        "json" -> "application/json"
        "xml" -> "application/xml"
        "html", "htm" -> "text/html"
        "zip" -> "application/zip"
        "gz" -> "application/gzip"
        "tar" -> "application/x-tar"
        "apk" -> "application/vnd.android.package-archive"
        else -> "application/octet-stream"
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            try {
                nm.deleteNotificationChannel("deskconn_session")
            } catch (e: Exception) {
                // Ignore
            }
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(channelId, "Deskconn", NotificationManager.IMPORTANCE_LOW)
                        .apply {
                            setShowBadge(false)
                            setSound(null, null)
                            enableVibration(false)
                            enableLights(false)
                        }
                )
            }
        }
    }

    private fun showNotification() {
        ensureNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notifId)
        }
        val closePi = PendingIntent.getBroadcast(
            this, 0,
            Intent(this, TerminalNotificationActionReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_bg_service_small)
            .setContentTitle("Deskconn")
            .setContentText("Deskconn is running")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSilent(true)
            .addAction(0, "Close", closePi)
            .build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(notifId, n)
    }

    private fun hideNotification() {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId)
    }
}
