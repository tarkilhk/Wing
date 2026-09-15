package com.tarkilhk.wing

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/** Raises the priority of the process that owns the real Dart event clients. */
class BackgroundMonitoringService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Never display a monitoring claim after process death without clients.
        if (MonitoringRuntime.engine == null ||
            !NotificationManagerCompat.from(this).areNotificationsEnabled()
        ) {
            MonitoringRuntime.startFailed()
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(
                    channelId, "Background monitoring", NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Keeps connected Hermes chats available outside Wing"
                    setShowBadge(false)
                })
                check(manager.getNotificationChannel(channelId).importance != NotificationManager.IMPORTANCE_NONE)
            }
            val open = PendingIntent.getActivity(
                this, notificationId,
                Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.drawable.ic_stat_connection)
                .setContentTitle("Monitoring Hermes")
                .setContentText("Keeping connected chats active for completion and attention alerts.")
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setGroup(groupKey)
                .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
            val notification = builder.build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(notificationId, notification)
            }
            // A complete group keeps the connection separate from chat alerts.
            // Android 16 can regroup a lone child or a summary without children.
            manager.notify(summaryId, builder.setGroupSummary(true).build())
            if (wakeLock == null) {
                wakeLock = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:hermes-monitoring")
                    .apply { setReferenceCounted(false); acquire() }
            }
            MonitoringRuntime.started(this)
        } catch (_: Exception) {
            MonitoringRuntime.startFailed()
            stopSelf()
        }
        // Reopening Wing restores connections; don't resurrect an empty engine.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).cancel(summaryId)
        MonitoringRuntime.serviceDestroyed()
        super.onDestroy()
    }

    companion object {
        private const val channelId = "hermes_monitoring"
        private const val notificationId = 214601
        private const val summaryId = 214602
        private const val groupKey = "wing_connection"
    }
}
