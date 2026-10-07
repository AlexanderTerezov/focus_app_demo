import 'package:flutter/services.dart';

import 'channel_contract.dart';
import 'foreground_activity.dart';

class AnalyticsPlugin {
  const AnalyticsPlugin();

  static const MethodChannel _methodChannel = MethodChannel(
    AnalyticsPluginChannelContract.methodChannelName,
  );

  Future<bool> isSupported() async {
    try {
      return await _methodChannel.invokeMethod<bool>(
            AnalyticsPluginChannelContract.isSupportedMethod,
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> hasUsageAccess() async {
    return await _methodChannel.invokeMethod<bool>(
          AnalyticsPluginChannelContract.hasUsageAccessMethod,
        ) ??
        false;
  }

  /// Opens Android Usage Access settings and completes after the user returns.
  Future<void> openUsageAccessSettings() {
    return _methodChannel.invokeMethod<void>(
      AnalyticsPluginChannelContract.openUsageAccessSettingsMethod,
    );
  }

  Future<bool> hasNotificationPermission() async {
    return await _methodChannel.invokeMethod<bool>(
          AnalyticsPluginChannelContract.hasNotificationPermissionMethod,
        ) ??
        false;
  }

  Future<bool> requestNotificationPermission() async {
    return await _methodChannel.invokeMethod<bool>(
          AnalyticsPluginChannelContract.requestNotificationPermissionMethod,
        ) ??
        false;
  }

  Future<void> startSession() {
    return _methodChannel.invokeMethod<void>(
      AnalyticsPluginChannelContract.startSessionMethod,
    );
  }

  Future<void> stopSession() {
    return _methodChannel.invokeMethod<void>(
      AnalyticsPluginChannelContract.stopSessionMethod,
    );
  }

  Future<void> showNotification(String text) {
    return _methodChannel.invokeMethod<void>(
      AnalyticsPluginChannelContract.showNotificationMethod,
      text,
    );
  }

  Future<ForegroundActivity?> getForegroundActivity() async {
    final values = await _methodChannel.invokeMapMethod<String, String?>(
      AnalyticsPluginChannelContract.getForegroundActivityMethod,
    );

    if (values == null) return null;

    final applicationName =
        values[AnalyticsPluginChannelContract.applicationNameKey];

    if (applicationName == null) return null;

    return ForegroundActivity(
      applicationName: applicationName,
      windowTitle: values[AnalyticsPluginChannelContract.windowTitleKey],
    );
  }
}
