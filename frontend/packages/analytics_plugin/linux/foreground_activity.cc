#include "foreground_activity.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

#include <cstring>
#include <initializer_list>
#include <regex>
#include <vector>

namespace analytics_plugin {
namespace {

constexpr char kKwinScript[] =
    "var w=workspace.activeWindow;"
    "output_result(JSON.stringify(w?{app:w.resourceClass,"
    "title:w.caption}:{}));";

bool Run(std::initializer_list<const gchar*> command,
         std::string* output,
         bool shared_temp = false) {
  std::vector<const gchar*> args = {"timeout", "2s"};
  args.insert(args.end(), command.begin(), command.end());
  args.push_back(nullptr);

  const auto flags = static_cast<GSubprocessFlags>(
      G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_SILENCE);
  g_autoptr(GSubprocessLauncher) launcher = g_subprocess_launcher_new(flags);

  const gchar* runtime_dir = g_getenv("XDG_RUNTIME_DIR");
  if (shared_temp && runtime_dir != nullptr && *runtime_dir != '\0') {
    g_subprocess_launcher_setenv(launcher, "TMPDIR", runtime_dir, TRUE);
  }

  g_autoptr(GSubprocess) process =
      g_subprocess_launcher_spawnv(launcher, args.data(), nullptr);
  if (process == nullptr) return false;

  g_autofree gchar* text = nullptr;
  if (!g_subprocess_communicate_utf8(
          process, nullptr, nullptr, &text, nullptr, nullptr) ||
      !g_subprocess_get_successful(process)) {
    return false;
  }

  *output = text == nullptr ? "" : text;
  return true;
}

FlValue* ParseJson(const std::string& text) {
  g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
  return fl_json_message_codec_decode(codec, text.c_str(), nullptr);
}

std::string GetString(FlValue* object, const char* key) {
  if (object == nullptr || fl_value_get_type(object) != FL_VALUE_TYPE_MAP) {
    return {};
  }

  FlValue* value = fl_value_lookup_string(object, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : "";
}

bool ParseSimple(const std::string& text,
                 const char* app_key,
                 const char* title_key,
                 ForegroundActivity* activity) {
  g_autoptr(FlValue) root = ParseJson(text);
  if (root == nullptr || fl_value_get_type(root) != FL_VALUE_TYPE_MAP) {
    return false;
  }

  activity->application_name = GetString(root, app_key);
  activity->window_title = GetString(root, title_key);
  return true;
}

FlValue* FindFocused(FlValue* node) {
  if (node == nullptr || fl_value_get_type(node) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }

  FlValue* focused = fl_value_lookup_string(node, "focused");
  if (focused != nullptr &&
      fl_value_get_type(focused) == FL_VALUE_TYPE_BOOL &&
      fl_value_get_bool(focused)) {
    return node;
  }

  for (const char* key : {"nodes", "floating_nodes"}) {
    FlValue* children = fl_value_lookup_string(node, key);
    if (children == nullptr ||
        fl_value_get_type(children) != FL_VALUE_TYPE_LIST) {
      continue;
    }

    for (size_t i = 0; i < fl_value_get_length(children); ++i) {
      FlValue* match = FindFocused(fl_value_get_list_value(children, i));
      if (match != nullptr) return match;
    }
  }

  return nullptr;
}

std::string Capture(const std::string& text, const char* pattern) {
  std::smatch match;
  return std::regex_search(text, match, std::regex(pattern))
             ? match[1].str()
             : "";
}

std::string Trim(const std::string& text) {
  g_autofree gchar* copy = g_strdup(text.c_str());
  return g_strstrip(copy);
}

bool ReadX11(ForegroundActivity* activity) {
  std::string root;
  if (!Run({"xprop", "-root", "_NET_ACTIVE_WINDOW"}, &root)) return false;

  const std::string id = Capture(root, R"re((0x[0-9a-fA-F]+))re");
  if (id.empty()) return false;
  if (id == "0x0") return true;

  std::string properties;
  if (!Run({"xprop", "-id", id.c_str(),
            "WM_CLASS", "_NET_WM_NAME", "WM_NAME"}, &properties)) {
    return false;
  }

  activity->application_name = Capture(
      properties, R"re(WM_CLASS[^\n]*= "[^"]*", "([^"]*)")re");
  if (activity->application_name.empty()) {
    activity->application_name =
        Capture(properties, R"re(WM_CLASS[^\n]*= "([^"]*)")re");
  }

  activity->window_title =
      Capture(properties, R"re(_NET_WM_NAME[^\n]*= "([^"]*)")re");
  if (activity->window_title.empty()) {
    activity->window_title =
        Capture(properties, R"re(WM_NAME[^\n]*= "([^"]*)")re");
  }

  return true;
}

bool ReadKde(ForegroundActivity* activity) {
  std::string text;
  if (Run({"kdotool", "kwinscript", "--inline", kKwinScript},
          &text, true) &&
      ParseSimple(text, "app", "title", activity)) {
    return true;
  }

  std::string app;
  std::string title;
  if (!Run({"kdotool", "getactivewindow", "getwindowclassname"},
           &app, true) ||
      !Run({"kdotool", "getactivewindow", "getwindowname"},
           &title, true)) {
    return false;
  }

  activity->application_name = Trim(app);
  activity->window_title = Trim(title);
  return true;
}

bool ReadGnome(ForegroundActivity* activity) {
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return false;

  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus,
      "org.gnome.Shell",
      "/org/gnome/shell/extensions/FocusedWindow",
      "org.gnome.shell.extensions.FocusedWindow",
      "Get",
      nullptr,
      G_VARIANT_TYPE("(s)"),
      G_DBUS_CALL_FLAGS_NONE,
      2000,
      nullptr,
      nullptr);
  if (reply == nullptr) return false;

  const gchar* json = nullptr;
  g_variant_get(reply, "(&s)", &json);
  return ParseSimple(json == nullptr ? "" : json,
                     "wm_class", "title", activity);
}

bool ReadHyprland(ForegroundActivity* activity) {
  std::string text;
  return Run({"hyprctl", "-j", "activewindow"}, &text) &&
         ParseSimple(text, "class", "title", activity);
}

bool ReadNiri(ForegroundActivity* activity) {
  std::string text;
  return Run({"niri", "msg", "--json", "focused-window"}, &text) &&
         ParseSimple(text, "app_id", "title", activity);
}

bool ReadSway(ForegroundActivity* activity) {
  std::string text;
  if (!Run({"swaymsg", "-r", "-t", "get_tree"}, &text)) return false;

  g_autoptr(FlValue) root = ParseJson(text);
  if (root == nullptr || fl_value_get_type(root) != FL_VALUE_TYPE_MAP) {
    return false;
  }

  FlValue* focused = FindFocused(root);
  if (focused == nullptr) return true;

  activity->application_name = GetString(focused, "app_id");
  if (activity->application_name.empty()) {
    FlValue* properties = fl_value_lookup_string(focused, "window_properties");
    activity->application_name = GetString(properties, "class");
  }
  activity->window_title = GetString(focused, "name");
  return true;
}

bool ReadWlroots(ForegroundActivity* activity) {
  std::string text;
  if (!Run({"wlrctl", "toplevel", "list", "state:active"}, &text)) {
    return false;
  }

  const std::string line = text.substr(0, text.find('\n'));
  const size_t separator = line.find(": ");
  if (separator == std::string::npos) return true;

  activity->application_name = line.substr(0, separator);
  activity->window_title = line.substr(separator + 2);
  return true;
}

}  // namespace

bool ReadForegroundActivity(Backend backend, ForegroundActivity* activity) {
  if (activity == nullptr) return false;
  *activity = {};

  switch (backend) {
    case Backend::x11:
      return ReadX11(activity);
    case Backend::kde:
      return ReadKde(activity);
    case Backend::gnome:
      return ReadGnome(activity);
    case Backend::hyprland:
      return ReadHyprland(activity);
    case Backend::sway:
      return ReadSway(activity);
    case Backend::niri:
      return ReadNiri(activity);
    case Backend::wlroots:
      return ReadWlroots(activity);
    case Backend::none:
      return false;
  }

  return false;
}

Backend DetectBackend() {
  ForegroundActivity ignored;
  const bool wayland =
      g_strcmp0(g_getenv("XDG_SESSION_TYPE"), "wayland") == 0 ||
      g_getenv("WAYLAND_DISPLAY") != nullptr;

  if (!wayland) {
    return g_getenv("DISPLAY") != nullptr &&
                   ReadForegroundActivity(Backend::x11, &ignored)
               ? Backend::x11
               : Backend::none;
  }

  const gchar* desktop_name = g_getenv("XDG_CURRENT_DESKTOP");
  g_autofree gchar* desktop =
      g_ascii_strdown(desktop_name == nullptr ? "" : desktop_name, -1);

  if (std::strstr(desktop, "kde") != nullptr &&
      ReadForegroundActivity(Backend::kde, &ignored)) {
    return Backend::kde;
  }
  if (std::strstr(desktop, "gnome") != nullptr &&
      ReadForegroundActivity(Backend::gnome, &ignored)) {
    return Backend::gnome;
  }
  if (g_getenv("HYPRLAND_INSTANCE_SIGNATURE") != nullptr &&
      ReadForegroundActivity(Backend::hyprland, &ignored)) {
    return Backend::hyprland;
  }
  if (g_getenv("SWAYSOCK") != nullptr &&
      ReadForegroundActivity(Backend::sway, &ignored)) {
    return Backend::sway;
  }
  if (g_getenv("NIRI_SOCKET") != nullptr &&
      ReadForegroundActivity(Backend::niri, &ignored)) {
    return Backend::niri;
  }
  if (ReadForegroundActivity(Backend::wlroots, &ignored)) {
    return Backend::wlroots;
  }

  return Backend::none;
}

}  // namespace analytics_plugin
