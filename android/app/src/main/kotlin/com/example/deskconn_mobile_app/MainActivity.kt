package com.example.deskconn_mobile_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val shellChannel = "deskconn/shell_notification"
    private val notifChannel = "deskconn/notification"
    private val fileChannel = "deskconn/file"
    private val channelId = "deskconn_session_v2"
    private val notifId = 1107

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
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
