#ifndef FLUTTER_PLUGIN_ANALYTICS_PLUGIN_H_
#define FLUTTER_PLUGIN_ANALYTICS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>
#include <string>

namespace analytics_plugin {

class AnalyticsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  explicit AnalyticsPlugin(HWND window_handle);
  ~AnalyticsPlugin() override;

  AnalyticsPlugin(const AnalyticsPlugin&) = delete;
  AnalyticsPlugin& operator=(const AnalyticsPlugin&) = delete;

 private:
  bool EnsureNotificationIcon();
  bool ShowNotification(const std::string& text);
  void RemoveNotificationIcon();

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND window_handle_;
  bool notification_icon_added_ = false;
  bool session_active_ = false;
};

}  // namespace analytics_plugin

#endif  // FLUTTER_PLUGIN_ANALYTICS_PLUGIN_H_
