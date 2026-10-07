abstract final class AnalyticsPluginChannelContract {
  static const methodChannelName = 'analytics_plugin/methods';

  static const isSupportedMethod = 'isSupported';
  static const hasUsageAccessMethod = 'hasUsageAccess';
  static const openUsageAccessSettingsMethod = 'openUsageAccessSettings';
  static const hasNotificationPermissionMethod = 'hasNotificationPermission';
  static const requestNotificationPermissionMethod =
      'requestNotificationPermission';
  static const startSessionMethod = 'startSession';
  static const stopSessionMethod = 'stopSession';
  static const getForegroundActivityMethod = 'getForegroundActivity';
  static const showNotificationMethod = 'showNotification';

  static const applicationNameKey = 'applicationName';
  static const windowTitleKey = 'windowTitle';
}
