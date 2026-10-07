#ifndef ANALYTICS_PLUGIN_LINUX_FOREGROUND_ACTIVITY_H_
#define ANALYTICS_PLUGIN_LINUX_FOREGROUND_ACTIVITY_H_

#include <string>

namespace analytics_plugin {

enum class Backend {
  none,
  x11,
  kde,
  gnome,
  hyprland,
  sway,
  niri,
  wlroots,
};

struct ForegroundActivity {
  std::string application_name;
  std::string window_title;
};

Backend DetectBackend();
bool ReadForegroundActivity(Backend backend, ForegroundActivity* activity);

}  // namespace analytics_plugin

#endif  // ANALYTICS_PLUGIN_LINUX_FOREGROUND_ACTIVITY_H_
