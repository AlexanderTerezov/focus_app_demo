package com.example.analytics_plugin

import android.Manifest
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class AnalyticsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var applicationContext: Context
    private lateinit var channel: MethodChannel

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingUsageAccessSettingsResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    private var sessionActive = false
    private var lastForegroundPackage: String? = null
    private var lastQueryTimeMillis = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        completePendingUsageAccessSettingsRequest(
            code = "plugin_detached",
            message = "The plugin detached before Usage Access settings returned.",
        )
        completePendingNotificationPermissionRequest(
            code = "plugin_detached",
            message = "The plugin detached before permission was resolved.",
        )
        clearSession()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            IS_SUPPORTED_METHOD -> result.success(true)
            HAS_USAGE_ACCESS_METHOD -> result.success(hasUsageAccess())
            OPEN_USAGE_ACCESS_SETTINGS_METHOD -> openUsageAccessSettings(result)
            HAS_NOTIFICATION_PERMISSION_METHOD ->
                result.success(hasNotificationPermission())
            REQUEST_NOTIFICATION_PERMISSION_METHOD ->
                requestNotificationPermission(result)
            START_SESSION_METHOD -> startSession(result)
            STOP_SESSION_METHOD -> {
                clearSession()
                result.success(null)
            }
            GET_FOREGROUND_ACTIVITY_METHOD -> getForegroundActivity(result)
            SHOW_NOTIFICATION_METHOD -> showNotification(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity(
            code = "activity_recreated",
            message = "The Android activity changed during a system request.",
        )
    }

    override fun onReattachedToActivityForConfigChanges(
        binding: ActivityPluginBinding,
    ) {
        attachToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachFromActivity(
            code = "activity_detached",
            message = "No Android activity is available for the system request.",
        )
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != USAGE_ACCESS_SETTINGS_REQUEST_CODE) {
            return false
        }

        val pendingResult = pendingUsageAccessSettingsResult ?: return true
        pendingUsageAccessSettingsResult = null
        pendingResult.success(null)
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) {
            return false
        }

        val pendingResult = pendingNotificationPermissionResult ?: return true
        pendingNotificationPermissionResult = null

        val permissionIndex =
            permissions.indexOf(Manifest.permission.POST_NOTIFICATIONS)
        val permissionGranted =
            permissionIndex >= 0 &&
                grantResults.getOrNull(permissionIndex) ==
                PackageManager.PERMISSION_GRANTED &&
                hasNotificationPermission()

        pendingResult.success(permissionGranted)
        return true
    }

    private fun attachToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    private fun detachFromActivity(
        code: String,
        message: String,
    ) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        completePendingUsageAccessSettingsRequest(code, message)
        completePendingNotificationPermissionRequest(code, message)
    }

    private fun hasUsageAccess(): Boolean {
        val appOpsManager =
            applicationContext.getSystemService(AppOpsManager::class.java)
                ?: return false

        return try {
            appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                applicationContext.packageName,
            ) == AppOpsManager.MODE_ALLOWED
        } catch (_: SecurityException) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun openUsageAccessSettings(result: MethodChannel.Result) {
        if (pendingUsageAccessSettingsResult != null) {
            result.error(
                "usage_access_settings_in_progress",
                "Usage Access settings are already open.",
                null,
            )
            return
        }

        val activity = activityBinding?.activity

        if (activity == null) {
            result.error(
                "activity_unavailable",
                "An Android activity is required to open Usage Access settings.",
                null,
            )
            return
        }

        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)

        if (intent.resolveActivity(activity.packageManager) == null) {
            result.error(
                "usage_access_settings_unavailable",
                "Android could not open Usage Access settings.",
                null,
            )
            return
        }

        pendingUsageAccessSettingsResult = result

        try {
            activity.startActivityForResult(
                intent,
                USAGE_ACCESS_SETTINGS_REQUEST_CODE,
            )
        } catch (error: RuntimeException) {
            pendingUsageAccessSettingsResult = null
            result.error(
                "usage_access_settings_unavailable",
                error.message ?: "Android could not open Usage Access settings.",
                null,
            )
        }
    }

    private fun hasNotificationPermission(): Boolean {
        val notificationManager =
            applicationContext.getSystemService(NotificationManager::class.java)
                ?: return false

        if (!notificationManager.areNotificationsEnabled()) {
            return false
        }

        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            applicationContext.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(false)
            return
        }

        if (
            applicationContext.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(false)
            return
        }

        if (pendingNotificationPermissionResult != null) {
            result.error(
                "permission_request_in_progress",
                "A notification permission request is already in progress.",
                null,
            )
            return
        }

        val activity = activityBinding?.activity

        if (activity == null) {
            result.error(
                "activity_unavailable",
                "An Android activity is required to request notification permission.",
                null,
            )
            return
        }

        pendingNotificationPermissionResult = result

        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE,
            )
        } catch (error: RuntimeException) {
            pendingNotificationPermissionResult = null
            result.error(
                "notification_permission_request_failed",
                error.message ?: "Android could not request notification permission.",
                null,
            )
        }
    }

    private fun startSession(result: MethodChannel.Result) {
        if (sessionActive) {
            result.success(null)
            return
        }

        if (!hasUsageAccess()) {
            result.error(
                "usage_access_required",
                "Usage Access must be enabled before analytics can start.",
                null,
            )
            return
        }

        val now = System.currentTimeMillis()
        lastQueryTimeMillis = maxOf(0L, now - INITIAL_LOOKBACK_MILLIS)
        lastForegroundPackage =
            readLatestForegroundPackage(lastQueryTimeMillis, now)
        lastQueryTimeMillis = maxOf(0L, now - QUERY_OVERLAP_MILLIS)
        sessionActive = true

        result.success(null)
    }

    private fun clearSession() {
        sessionActive = false
        lastForegroundPackage = null
        lastQueryTimeMillis = 0L
    }

    private fun getForegroundActivity(result: MethodChannel.Result) {
        if (!sessionActive || !hasUsageAccess()) {
            result.success(null)
            return
        }

        val now = System.currentTimeMillis()
        val detectedPackage =
            readLatestForegroundPackage(lastQueryTimeMillis, now)

        lastQueryTimeMillis = maxOf(0L, now - QUERY_OVERLAP_MILLIS)

        if (detectedPackage != null) {
            lastForegroundPackage = detectedPackage
        }

        val foregroundPackage = lastForegroundPackage

        if (foregroundPackage == null) {
            result.success(null)
            return
        }

        result.success(
            mapOf<String, Any?>(
                APPLICATION_NAME_KEY to foregroundPackage,
                WINDOW_TITLE_KEY to null,
            ),
        )
    }

    private fun readLatestForegroundPackage(
        beginTimeMillis: Long,
        endTimeMillis: Long,
    ): String? {
        val usageStatsManager =
            applicationContext.getSystemService(UsageStatsManager::class.java)
                ?: return null
        val events =
            usageStatsManager.queryEvents(beginTimeMillis, endTimeMillis)
                ?: return null

        var latestPackage: String? = null
        var latestTimestamp = Long.MIN_VALUE
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            if (
                isForegroundEvent(event.eventType) &&
                event.timeStamp >= latestTimestamp
            ) {
                latestPackage = event.packageName?.takeIf(String::isNotBlank)
                latestTimestamp = event.timeStamp
            }
        }

        return latestPackage
    }

    @Suppress("DEPRECATION")
    private fun isForegroundEvent(eventType: Int): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            eventType == UsageEvents.Event.ACTIVITY_RESUMED
        } else {
            eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
        }
    }

    @Suppress("DEPRECATION")
    private fun showNotification(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!sessionActive) {
            result.error(
                "session_inactive",
                "A notification cannot be shown outside an active session.",
                null,
            )
            return
        }

        val text = call.arguments as? String

        if (text.isNullOrBlank()) {
            result.error(
                "invalid_notification_text",
                "Notification text must be a non-empty string.",
                null,
            )
            return
        }

        if (!hasNotificationPermission()) {
            result.error(
                "notification_permission_required",
                "Notification permission is required to show focus reminders.",
                null,
            )
            return
        }

        val notificationManager =
            applicationContext.getSystemService(NotificationManager::class.java)

        if (notificationManager == null) {
            result.error(
                "notification_failed",
                "Android's notification service is unavailable.",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(
                    applicationContext,
                    NOTIFICATION_CHANNEL_ID,
                )
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(applicationContext)
            }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_ALL)
        }

        val notification =
            builder
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(NOTIFICATION_TITLE)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .build()

        try {
            notificationManager.notify(NOTIFICATION_ID, notification)
            result.success(null)
        } catch (_: SecurityException) {
            result.error(
                "notification_permission_required",
                "Notification permission is required to show focus reminders.",
                null,
            )
        }
    }

    private fun completePendingUsageAccessSettingsRequest(
        code: String,
        message: String,
    ) {
        pendingUsageAccessSettingsResult?.error(code, message, null)
        pendingUsageAccessSettingsResult = null
    }

    private fun completePendingNotificationPermissionRequest(
        code: String,
        message: String,
    ) {
        pendingNotificationPermissionResult?.error(code, message, null)
        pendingNotificationPermissionResult = null
    }

    private companion object {
        const val METHOD_CHANNEL_NAME = "analytics_plugin/methods"

        const val IS_SUPPORTED_METHOD = "isSupported"
        const val HAS_USAGE_ACCESS_METHOD = "hasUsageAccess"
        const val OPEN_USAGE_ACCESS_SETTINGS_METHOD =
            "openUsageAccessSettings"
        const val HAS_NOTIFICATION_PERMISSION_METHOD =
            "hasNotificationPermission"
        const val REQUEST_NOTIFICATION_PERMISSION_METHOD =
            "requestNotificationPermission"
        const val START_SESSION_METHOD = "startSession"
        const val STOP_SESSION_METHOD = "stopSession"
        const val GET_FOREGROUND_ACTIVITY_METHOD =
            "getForegroundActivity"
        const val SHOW_NOTIFICATION_METHOD = "showNotification"

        const val APPLICATION_NAME_KEY = "applicationName"
        const val WINDOW_TITLE_KEY = "windowTitle"

        const val INITIAL_LOOKBACK_MILLIS = 60_000L
        const val QUERY_OVERLAP_MILLIS = 1_000L

        const val USAGE_ACCESS_SETTINGS_REQUEST_CODE = 7642
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7643
        const val NOTIFICATION_CHANNEL_ID = "focus_alerts"
        const val NOTIFICATION_CHANNEL_NAME = "Focus alerts"
        const val NOTIFICATION_TITLE = "Focus reminder"
        const val NOTIFICATION_ID = 1
    }
}
