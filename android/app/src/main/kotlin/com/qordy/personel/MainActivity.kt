package com.qordy.personel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val methodChannelName = "com.qordy.personel/pda_scanner"
    private val eventChannelName = "com.qordy.personel/pda_scanner_events"
    private var eventSink: EventChannel.EventSink? = null
    private var scanReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> {
                        val zebraAction = call.argument<String>("zebraAction")
                            ?: "com.symbol.datawedge.ACTION_BROADCAST"
                        val honeywellAction = call.argument<String>("honeywellAction")
                            ?: "com.honeywell.decode.intent.action.SCAN_RESULT"
                        registerScanReceiver(zebraAction, honeywellAction)
                        result.success(true)
                    }
                    "softTrigger" -> {
                        val triggerIntent = Intent("com.symbol.datawedge.api.ACTION").apply {
                            putExtra("com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "START_SCANNING")
                        }
                        sendBroadcast(triggerIntent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerScanReceiver(zebraAction: String, honeywellAction: String) {
        unregisterScanReceiver()
        val filter = IntentFilter().apply {
            addAction(zebraAction)
            addAction("com.symbol.datawedge.api.ACTION")
            addAction(honeywellAction)
        }
        scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val barcode = intent.getStringExtra("com.symbol.datawedge.data_string")
                    ?: intent.getStringExtra("data")
                    ?: intent.getStringExtra("barcode_string")
                    ?: return
                val symbology = intent.getStringExtra("com.symbol.datawedge.label_type")
                    ?: intent.getStringExtra("codeId")
                    ?: "UNKNOWN"
                eventSink?.success(
                    mapOf(
                        "barcode" to barcode,
                        "symbology" to symbology
                    )
                )
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(scanReceiver, filter)
        }
    }

    private fun unregisterScanReceiver() {
        scanReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
            scanReceiver = null
        }
    }

    override fun onDestroy() {
        unregisterScanReceiver()
        super.onDestroy()
    }
}
