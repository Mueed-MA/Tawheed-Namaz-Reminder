package com.tawheed.namazreminder

import android.hardware.GeomagneticField
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val qiblaChannel = "com.tawheed.namazreminder/qibla"
    private val jamatNotificationChannel = "com.tawheed.namazreminder/jamat_notification"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, qiblaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMagneticDeclination" -> {
                        val latitude = call.argument<Double>("latitude")
                        val longitude = call.argument<Double>("longitude")
                        val altitude = call.argument<Double>("altitude") ?: 0.0
                        val timeMillis = call.argument<Number>("timeMillis")?.toLong()
                            ?: System.currentTimeMillis()

                        if (latitude == null || longitude == null) {
                            result.error(
                                "INVALID_ARGS",
                                "Latitude and longitude are required.",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val field = GeomagneticField(
                            latitude.toFloat(),
                            longitude.toFloat(),
                            altitude.toFloat(),
                            timeMillis
                        )
                        result.success(field.declination.toDouble())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, jamatNotificationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleReplacement" -> {
                        val notificationId = call.argument<Int>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val payload = call.argument<String>("payload")
                        val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
                        val endTimeMillis = call.argument<Number>("endTimeMillis")?.toLong()
                        val jamatTimeMillis = call.argument<Number>("jamatTimeMillis")?.toLong()
                        val repeatMode = call.argument<String>("repeatMode")

                        if (
                            notificationId == null ||
                            title == null ||
                            body == null ||
                            payload == null ||
                            triggerAtMillis == null ||
                            endTimeMillis == null ||
                            jamatTimeMillis == null ||
                            repeatMode == null
                        ) {
                            result.error(
                                "INVALID_ARGS",
                                "Missing arguments for replacement notification scheduling.",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        NativeJamatNotificationScheduler.schedule(
                            context = applicationContext,
                            notificationId = notificationId,
                            title = title,
                            body = body,
                            payload = payload,
                            triggerAtMillis = triggerAtMillis,
                            endTimeMillis = endTimeMillis,
                            jamatTimeMillis = jamatTimeMillis,
                            repeatMode = repeatMode,
                        )
                        result.success(null)
                    }
                    "cancelReplacement" -> {
                        val notificationId = call.argument<Int>("id")
                        if (notificationId == null) {
                            result.error("INVALID_ARGS", "Notification id is required.", null)
                            return@setMethodCallHandler
                        }
                        NativeJamatNotificationScheduler.cancel(applicationContext, notificationId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
