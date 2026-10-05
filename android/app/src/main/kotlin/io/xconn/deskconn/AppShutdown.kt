package io.xconn.deskconn

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import id.flutter.flutter_background_service.BackgroundService

object AppShutdown {
    fun shutdown(context: Context) {
        context.getSharedPreferences("id.flutter.background_service", Context.MODE_PRIVATE)
            .edit().putBoolean("is_manually_stopped", true).commit()
        context.stopService(Intent(context, BackgroundService::class.java))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
        android.os.Process.killProcess(android.os.Process.myPid())
    }
}
