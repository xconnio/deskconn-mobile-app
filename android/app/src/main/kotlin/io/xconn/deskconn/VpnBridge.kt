package io.xconn.deskconn

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

object VpnBridge {
    private const val CONTROL_CHANNEL = "deskconn/vpn"
    private const val PACKET_CHANNEL = "deskconn/vpn_packets"
    private const val MAX_BATCH = 256

    private val main = Handler(Looper.getMainLooper())
    private val incoming = ConcurrentLinkedQueue<ByteArray>()
    private val flushScheduled = AtomicBoolean(false)

    @Volatile
    private var sink: EventChannel.EventSink? = null
    private var control: MethodChannel? = null

    fun attach(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        val messenger = engine.dartExecutor.binaryMessenger

        control = MethodChannel(messenger, CONTROL_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val address = call.argument<String>("address")
                        val prefix = call.argument<Int>("prefix")
                        val mtu = call.argument<Int>("mtu")
                        if (address == null || prefix == null || mtu == null) {
                            result.error("INVALID_ARGS", "address, prefix and mtu are required", null)
                            return@setMethodCallHandler
                        }
                        DeskconnVpnService.start(appContext, address, prefix, mtu) { error ->
                            main.post {
                                if (error == null) result.success(null) else result.error("VPN_START_FAILED", error, null)
                            }
                        }
                    }
                    "stop" -> {
                        DeskconnVpnService.stop()
                        incoming.clear()
                        result.success(null)
                    }
                    "write" -> {
                        val packets = (call.arguments as? List<*>)?.filterIsInstance<ByteArray>().orEmpty()
                        DeskconnVpnService.write(packets)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        EventChannel(messenger, PACKET_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
                incoming.clear()
            }
        })
    }

    fun deliver(packet: ByteArray) {
        if (sink == null) return
        incoming.add(packet)
        if (flushScheduled.compareAndSet(false, true)) main.post(::flush)
    }

    private fun flush() {
        flushScheduled.set(false)
        val batch = ArrayList<ByteArray>()
        while (batch.size < MAX_BATCH) {
            batch.add(incoming.poll() ?: break)
        }
        if (batch.isNotEmpty()) sink?.success(batch)
        if (incoming.isNotEmpty() && flushScheduled.compareAndSet(false, true)) main.post(::flush)
    }

    fun revoked() {
        main.post { control?.invokeMethod("revoked", null) }
    }
}
