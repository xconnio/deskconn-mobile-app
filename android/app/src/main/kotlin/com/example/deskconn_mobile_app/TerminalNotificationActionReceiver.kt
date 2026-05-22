package com.example.deskconn_mobile_app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import id.flutter.flutter_background_service.BackgroundService

class TerminalNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        context.stopService(Intent(context, BackgroundService::class.java))
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancelAll()
        android.os.Process.killProcess(android.os.Process.myPid())
    }
}
