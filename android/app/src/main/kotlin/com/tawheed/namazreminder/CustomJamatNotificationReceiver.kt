package com.tawheed.namazreminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class CustomJamatNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        if (notificationId < 0) return

        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val payload = intent.getStringExtra(EXTRA_PAYLOAD).orEmpty()
        val endTimeMillis = intent.getLongExtra(EXTRA_END_TIME_MILLIS, 0L)
        val jamatTimeMillis = intent.getLongExtra(EXTRA_JAMAT_TIME_MILLIS, 0L)
        val originalTriggerAtMillis = intent.getLongExtra(EXTRA_TRIGGER_AT_MILLIS, 0L)
        val repeatMode = intent.getStringExtra(EXTRA_REPEAT_MODE).orEmpty()

        val notificationBody = body.ifBlank { "Jamat for $title is about to begin" }

        val contentIntent = buildContentIntent(
            context = context,
            notificationId = notificationId,
            payload = payload,
        )

        val customView = RemoteViews(context.packageName, R.layout.jamat_countdown_notification)
        customView.setTextViewText(R.id.jamat_label, notificationBody)
        customView.setViewVisibility(R.id.jamat_countdown, android.view.View.GONE)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(notificationBody)
            .setCustomContentView(customView)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setOngoing(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setTimeoutAfter(60_000L)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)

        if (repeatMode == REPEAT_DAILY || repeatMode == REPEAT_WEEKLY) {
            val interval = if (repeatMode == REPEAT_DAILY) DAY_MILLIS else WEEK_MILLIS
            val nextTriggerAtMillis = originalTriggerAtMillis + interval
            NativeJamatNotificationScheduler.schedule(
                context = context,
                notificationId = notificationId,
                title = title,
                body = notificationBody,
                payload = payload,
                triggerAtMillis = nextTriggerAtMillis,
                endTimeMillis = endTimeMillis + interval,
                jamatTimeMillis = jamatTimeMillis + interval,
                repeatMode = repeatMode,
            )
        }
    }

    private fun buildContentIntent(
        context: Context,
        notificationId: Int,
        payload: String,
    ): PendingIntent {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = SELECT_NOTIFICATION_ACTION
            putExtra(EXTRA_NOTIFICATION_ID_LEGACY, notificationId)
            putExtra(EXTRA_PAYLOAD_LEGACY, payload)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }

        return PendingIntent.getActivity(context, notificationId, launchIntent, flags)
    }

    companion object {
        const val CHANNEL_ID = "salah_alarm_channel_v7"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TRIGGER_AT_MILLIS = "trigger_at_millis"
        const val EXTRA_END_TIME_MILLIS = "end_time_millis"
        const val EXTRA_JAMAT_TIME_MILLIS = "jamat_time_millis"
        const val EXTRA_REPEAT_MODE = "repeat_mode"

        const val EXTRA_NOTIFICATION_ID_LEGACY = "notificationId"
        const val EXTRA_PAYLOAD_LEGACY = "payload"
        const val SELECT_NOTIFICATION_ACTION = "SELECT_NOTIFICATION"

        const val REPEAT_NONE = "none"
        const val REPEAT_DAILY = "daily"
        const val REPEAT_WEEKLY = "weekly"

        private const val DAY_MILLIS = 24L * 60L * 60L * 1000L
        private const val WEEK_MILLIS = 7L * DAY_MILLIS
        private const val REPLACEMENT_DELAY_MILLIS = 100L

        fun buildPendingIntent(context: Context, intent: Intent, requestCode: Int): PendingIntent {
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }

        fun createScheduleIntent(
            context: Context,
            notificationId: Int,
            title: String,
            body: String,
            payload: String,
            triggerAtMillis: Long,
            endTimeMillis: Long,
            jamatTimeMillis: Long,
            repeatMode: String,
        ): Intent {
            return Intent(context, CustomJamatNotificationReceiver::class.java).apply {
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_PAYLOAD, payload)
                putExtra(EXTRA_TRIGGER_AT_MILLIS, triggerAtMillis)
                putExtra(EXTRA_END_TIME_MILLIS, endTimeMillis)
                putExtra(EXTRA_JAMAT_TIME_MILLIS, jamatTimeMillis)
                putExtra(EXTRA_REPEAT_MODE, repeatMode)
            }
        }

        fun adjustedTriggerAtMillis(triggerAtMillis: Long): Long {
            return triggerAtMillis + REPLACEMENT_DELAY_MILLIS
        }
    }
}

object NativeJamatNotificationScheduler {
    fun schedule(
        context: Context,
        notificationId: Int,
        title: String,
        body: String,
        payload: String,
        triggerAtMillis: Long,
        endTimeMillis: Long,
        jamatTimeMillis: Long,
        repeatMode: String,
    ) {
        val intent = CustomJamatNotificationReceiver.createScheduleIntent(
            context = context,
            notificationId = notificationId,
            title = title,
            body = body,
            payload = payload,
            triggerAtMillis = triggerAtMillis,
            endTimeMillis = endTimeMillis,
            jamatTimeMillis = jamatTimeMillis,
            repeatMode = repeatMode,
        )
        val pendingIntent = CustomJamatNotificationReceiver.buildPendingIntent(
            context,
            intent,
            notificationId,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val scheduleAt = CustomJamatNotificationReceiver.adjustedTriggerAtMillis(triggerAtMillis)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                scheduleAt,
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, scheduleAt, pendingIntent)
        }
    }

    fun cancel(context: Context, notificationId: Int) {
        val intent = Intent(context, CustomJamatNotificationReceiver::class.java)
        val pendingIntent = CustomJamatNotificationReceiver.buildPendingIntent(
            context,
            intent,
            notificationId,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }
}
