package com.example.deskconn_mobile_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shellNotificationChannel = "deskconn/shell_notification"
    private val foregroundChannelId = "FOREGROUND_DEFAULT"
    private val shellActiveNotificationId = 1108

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1107)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == "deskconn.CLOSE_SHELL") {
            val realm = intent.getStringExtra("realm") ?: return
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, shellNotificationChannel)
                    .invokeMethod("closeShell", mapOf("realm" to realm))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shellNotificationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showShellNotification" -> {
                        val title = call.argument<String>("title") ?: "Deskconn Shell"
                        val content = call.argument<String>("content") ?: "Terminal is running"
                        val realm = call.argument<String>("realm")
                        showShellNotification(title, content, realm)
                        result.success(null)
                    }
                    "dismissShellNotification" -> {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancel(shellActiveNotificationId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun showShellNotification(title: String, content: String, realm: String?) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(foregroundChannelId, "Shell", NotificationManager.IMPORTANCE_LOW)
            )
        }

        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val closeIntent = Intent(this, MainActivity::class.java).apply {
            action = "deskconn.CLOSE_SHELL"
            putExtra("realm", realm)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val closePendingIntent = PendingIntent.getActivity(
            this, 1, closeIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, foregroundChannelId)
            .setSmallIcon(R.drawable.ic_bg_service_small)
            .setContentTitle(title)
            .setContentText(content)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openPendingIntent)
            .addAction(R.drawable.ic_bg_service_small, "Close", closePendingIntent)
            .build()

        notificationManager.notify(shellActiveNotificationId, notification)
    }
}
