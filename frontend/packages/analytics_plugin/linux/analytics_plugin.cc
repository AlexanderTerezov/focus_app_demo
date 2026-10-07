#include "include/analytics_plugin/analytics_plugin.h"

#include <gio/gio.h>

#include <cstring>

#include "foreground_activity.h"

namespace {

struct PluginState {
  bool session_active = false;
  analytics_plugin::Backend backend = analytics_plugin::Backend::none;
};

void HandleMethodCall(FlMethodChannel*,
                      FlMethodCall* call,
                      gpointer user_data) {
  auto* state = static_cast<PluginState*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (std::strcmp(method, "isSupported") == 0) {
    state->backend = analytics_plugin::DetectBackend();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(
            state->backend != analytics_plugin::Backend::none)));

  } else if (std::strcmp(method, "hasUsageAccess") == 0 ||
             std::strcmp(method, "hasNotificationPermission") == 0 ||
             std::strcmp(method, "requestNotificationPermission") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(true)));

  } else if (std::strcmp(method, "openUsageAccessSettings") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (std::strcmp(method, "startSession") == 0) {
    state->backend = analytics_plugin::DetectBackend();
    if (state->backend == analytics_plugin::Backend::none) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "unsupported", "No supported foreground-window interface is available.",
          nullptr));
    } else {
      state->session_active = true;
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }

  } else if (std::strcmp(method, "stopSession") == 0) {
    state->session_active = false;
    state->backend = analytics_plugin::Backend::none;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (std::strcmp(method, "getForegroundActivity") == 0) {
    analytics_plugin::ForegroundActivity activity;
    if (!state->session_active ||
        !analytics_plugin::ReadForegroundActivity(
            state->backend, &activity) ||
        activity.application_name.empty()) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      g_autoptr(FlValue) value = fl_value_new_map();
      fl_value_set_string_take(
          value, "applicationName",
          fl_value_new_string(activity.application_name.c_str()));
      if (!activity.window_title.empty()) {
        fl_value_set_string_take(
            value, "windowTitle",
            fl_value_new_string(activity.window_title.c_str()));
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
    }

  } else if (std::strcmp(method, "showNotification") == 0) {
    FlValue* argument = fl_method_call_get_args(call);
    if (!state->session_active) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "session_inactive", "The focus session has ended.", nullptr));
    } else if (argument == nullptr ||
               fl_value_get_type(argument) != FL_VALUE_TYPE_STRING ||
               *fl_value_get_string(argument) == '\0') {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_notification_text",
          "Notification text must be a non-empty string.", nullptr));
    } else {
      GApplication* application = g_application_get_default();
      if (application == nullptr) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "notifications_unavailable",
            "The desktop notification service is unavailable.", nullptr));
      } else {
        g_autoptr(GNotification) notification =
            g_notification_new("Focus reminder");
        g_notification_set_body(notification, fl_value_get_string(argument));
        g_application_send_notification(
            application, nullptr, notification);
        response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      }
    }

  } else {
    response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

extern "C" void analytics_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* state = new PluginState();

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "analytics_plugin/methods",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel,
      HandleMethodCall,
      state,
      [](gpointer data) { delete static_cast<PluginState*>(data); });
}
