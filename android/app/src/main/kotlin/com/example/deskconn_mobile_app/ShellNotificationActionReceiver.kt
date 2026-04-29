package com.example.deskconn_mobile_app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import id.flutter.flutter_background_service.BackgroundService

class ShellNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        context.stopService(Intent(context, BackgroundService::class.java))
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(1107)
    }
}
