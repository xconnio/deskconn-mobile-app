package com.example.deskconn_mobile_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shellNotificationChannel = "deskconn/shell_notification"

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
        val realm = intent.getStringExtra("realm") ?: return
        val method = when (intent.action) {
            "deskconn.OPEN_Terminal" -> "openTerminal"
            "deskconn.CLOSE_Terminal" -> "closeTerminal"
            else -> return
        }
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, shellNotificationChannel)
                .invokeMethod(method, mapOf("realm" to realm))
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
    }
}
