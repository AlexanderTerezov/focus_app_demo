#include "include/analytics_plugin/analytics_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "analytics_plugin.h"

void AnalyticsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  analytics_plugin::AnalyticsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
