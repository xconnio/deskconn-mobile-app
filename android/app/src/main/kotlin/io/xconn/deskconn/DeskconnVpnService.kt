package io.xconn.deskconn

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class DeskconnVpnService : VpnService() {
    private class StartRequest(val address: String, val prefix: Int, val mtu: Int, val done: (String?) -> Unit)

    companion object {
        private const val NOTIFICATION_ID = 1110

        @Volatile
        private var pending: StartRequest? = null

        @Volatile
        private var running: DeskconnVpnService? = null

        fun start(context: Context, address: String, prefix: Int, mtu: Int, done: (String?) -> Unit) {
            pending = StartRequest(address, prefix, mtu, done)
            context.startService(Intent(context, DeskconnVpnService::class.java))
        }

        fun stop() {
            running?.shutdown()
        }

        fun write(packets: List<ByteArray>) {
            running?.writePackets(packets)
        }
    }

    private var tun: ParcelFileDescriptor? = null
    private var output: FileOutputStream? = null
    private var reader: Thread? = null
    private var writer: ExecutorService? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val request = pending ?: return START_NOT_STICKY
        pending = null
        closeTunnel()
        try {
            val fd = establish(request)
            if (fd == null) {
                request.done("VPN permission is missing")
                stopSelf()
                return START_NOT_STICKY
            }
            tun = fd
            output = FileOutputStream(fd.fileDescriptor)
            writer = Executors.newSingleThreadExecutor()
            running = this
            startReader(fd)
            showNotification()
            request.done(null)
        } catch (e: Exception) {
            closeTunnel()
            Log.e("DeskconnVpn", "establish failed for ${request.address}/${request.prefix} mtu=${request.mtu}", e)
            request.done("${e.javaClass.simpleName}: ${e.message} (${request.address}/${request.prefix}, mtu ${request.mtu})")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun establish(request: StartRequest): ParcelFileDescriptor? = Builder()
        .setSession("Deskconn")
        .setMtu(request.mtu)
        .addAddress(request.address, request.prefix)
        .addRoute("0.0.0.0", 0)
        .addDisallowedApplication(packageName)
        .establish()

    private fun startReader(fd: ParcelFileDescriptor) {
        reader = Thread({
            val input = FileInputStream(fd.fileDescriptor)
            val buffer = ByteArray(32767)
            try {
                while (!Thread.currentThread().isInterrupted) {
                    val n = input.read(buffer)
                    if (n <= 0) continue
                    if ((buffer[0].toInt() shr 4) and 0xF != 4) continue
                    VpnBridge.deliver(buffer.copyOf(n))
                }
            } catch (e: IOException) {
            }
        }, "deskconn-vpn-reader").apply { start() }
    }

    private fun writePackets(packets: List<ByteArray>) {
        val out = output ?: return
        writer?.execute {
            try {
                for (packet in packets) out.write(packet)
            } catch (e: IOException) {
            }
        }
    }

    private fun showNotification() {
        AppNotification.ensureChannel(this)
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPi = PendingIntent.getActivity(
            this, 2, openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = NotificationCompat.Builder(this, AppNotification.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bg_service_small)
            .setContentTitle("Deskconn VPN")
            .setContentText("VPN connected")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openPi)
            .build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, n)
    }

    private fun closeTunnel() {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
        if (running === this) running = null
        reader?.interrupt()
        reader = null
        writer?.shutdownNow()
        writer = null
        try {
            output?.close()
        } catch (e: IOException) {
        }
        output = null
        try {
            tun?.close()
        } catch (e: IOException) {
        }
        tun = null
    }

    private fun shutdown() {
        closeTunnel()
        stopSelf()
    }

    override fun onRevoke() {
        val wasRunning = tun != null
        shutdown()
        if (wasRunning) VpnBridge.revoked()
    }

    override fun onDestroy() {
        closeTunnel()
        super.onDestroy()
    }
}
