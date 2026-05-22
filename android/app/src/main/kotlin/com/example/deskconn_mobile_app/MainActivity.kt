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
    private val shellChannel = "deskconn/shell_notification"
    private val notifChannel = "deskconn/notification"
    private val channelId = "deskconn_session"
    private val notifId = 1107

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notifId)
        }
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
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(channelId, "Deskconn", NotificationManager.IMPORTANCE_LOW)
                        .apply { setShowBadge(false) }
                )
            }
        }
    }

    private fun showNotification() {
        ensureNotificationChannel()
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
