#include "analytics_plugin.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

#include <cwchar>
#include <filesystem>
#include <memory>
#include <string>
#include <variant>

namespace analytics_plugin {
namespace {

constexpr char kMethodChannelName[] = "analytics_plugin/methods";
constexpr char kIsSupportedMethod[] = "isSupported";
constexpr char kStartSessionMethod[] = "startSession";
constexpr char kStopSessionMethod[] = "stopSession";
constexpr char kGetForegroundActivityMethod[] = "getForegroundActivity";
constexpr char kShowNotificationMethod[] = "showNotification";
constexpr char kApplicationNameKey[] = "applicationName";
constexpr char kWindowTitleKey[] = "windowTitle";

constexpr UINT kNotificationIconId = 1;
// Dart supplies the body text; Windows owns the fixed title and presentation.
constexpr wchar_t kNotificationTitle[] = L"Focus reminder";

constexpr DWORD kExecutablePathBufferSize = 32768;

struct ForegroundActivity {
  std::string application_name;
  std::string window_title;
};

std::string WideStringToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }

  const int utf8_length = WideCharToMultiByte(
      CP_UTF8,
      0,
      value.data(),
      static_cast<int>(value.size()),
      nullptr,
      0,
      nullptr,
      nullptr);

  if (utf8_length <= 0) {
    return {};
  }

  std::string utf8_value(utf8_length, '\0');

  WideCharToMultiByte(
      CP_UTF8,
      0,
      value.data(),
      static_cast<int>(value.size()),
      utf8_value.data(),
      utf8_length,
      nullptr,
      nullptr);

  return utf8_value;
}

std::wstring Utf8ToWideString(const std::string& value) {
  if (value.empty()) {
    return {};
  }

  const int wide_length = MultiByteToWideChar(
      CP_UTF8,
      MB_ERR_INVALID_CHARS,
      value.data(),
      static_cast<int>(value.size()),
      nullptr,
      0);

  if (wide_length <= 0) {
    return {};
  }

  std::wstring wide_value(wide_length, L'\0');

  MultiByteToWideChar(
      CP_UTF8,
      MB_ERR_INVALID_CHARS,
      value.data(),
      static_cast<int>(value.size()),
      wide_value.data(),
      wide_length);

  return wide_value;
}

std::string GetExecutableName(DWORD process_id) {
  // Open the process only to read its executable path.
  const HANDLE process_handle = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION,
      FALSE,
      process_id);

  if (process_handle == nullptr) {
    return {};
  }

  std::wstring executable_path(kExecutablePathBufferSize, L'\0');
  DWORD path_length = static_cast<DWORD>(executable_path.size());

  const bool path_was_read = QueryFullProcessImageNameW(
                                 process_handle,
                                 0,
                                 executable_path.data(),
                                 &path_length) != FALSE;

  CloseHandle(process_handle);

  if (!path_was_read || path_length == 0) {
    return {};
  }

  executable_path.resize(path_length);

  const std::wstring executable_name =
      std::filesystem::path(executable_path).filename().wstring();

  return WideStringToUtf8(executable_name);
}

std::string GetWindowTitle(HWND window) {
  const int title_length = GetWindowTextLengthW(window);

  if (title_length <= 0) {
    return {};
  }

  std::wstring window_title(title_length + 1, L'\0');
  const int copied_characters = GetWindowTextW(
      window,
      window_title.data(),
      static_cast<int>(window_title.size()));

  if (copied_characters <= 0) {
    return {};
  }

  window_title.resize(copied_characters);
  return WideStringToUtf8(window_title);
}

ForegroundActivity GetForegroundActivity() {
  // Find the window the user is currently working in.
  const HWND foreground_window = GetForegroundWindow();

  if (foreground_window == nullptr) {
    return {};
  }

  // Find the process that owns that window.
  DWORD process_id = 0;
  GetWindowThreadProcessId(foreground_window, &process_id);

  if (process_id == 0) {
    return {};
  }

  const std::string application_name = GetExecutableName(process_id);

  if (application_name.empty()) {
    return {};
  }

  return {
      application_name,
      GetWindowTitle(foreground_window),
  };
}

}  // namespace

void AnalyticsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto* view = registrar->GetView();
  auto plugin = std::make_unique<AnalyticsPlugin>(
      view == nullptr ? nullptr : view->GetNativeWindow());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](
          const auto& call,
          auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

AnalyticsPlugin::AnalyticsPlugin(HWND window_handle)
    : window_handle_(window_handle) {}

AnalyticsPlugin::~AnalyticsPlugin() {
  RemoveNotificationIcon();
}

// Windows requires a notification-area icon before Shell_NotifyIcon can
// display a banner associated with the application.
bool AnalyticsPlugin::EnsureNotificationIcon() {
  if (notification_icon_added_) {
    // Reuse the icon for every reminder during the active focus session.
    return true;
  }

  if (window_handle_ == nullptr) {
    return false;
  }

  NOTIFYICONDATAW icon_data{};
  icon_data.cbSize = sizeof(icon_data);
  icon_data.hWnd = window_handle_;
  icon_data.uID = kNotificationIconId;
  icon_data.uFlags = NIF_ICON | NIF_TIP;
  icon_data.hIcon = LoadIconW(nullptr, IDI_INFORMATION);

  if (icon_data.hIcon == nullptr) {
    return false;
  }

  // Copy the tooltip into Windows' fixed-size buffer, truncating it safely
  // and preserving the terminating null character if necessary.
  wcsncpy_s(
      icon_data.szTip,
      sizeof(icon_data.szTip) / sizeof(icon_data.szTip[0]),
      L"Focus App",
      _TRUNCATE);

  // Register the icon with the taskbar before using it for notifications.
  if (Shell_NotifyIconW(NIM_ADD, &icon_data) == FALSE) {
    return false;
  }

  icon_data.uVersion = NOTIFYICON_VERSION_4;
  // Tell Windows to use its current notification-area interaction behavior.
  Shell_NotifyIconW(NIM_SETVERSION, &icon_data);

  notification_icon_added_ = true;
  return true;
}

bool AnalyticsPlugin::ShowNotification(const std::string& text) {
  // Flutter sends UTF-8 text, while the Windows API expects a wide string.
  const std::wstring notification_text = Utf8ToWideString(text);

  if (notification_text.empty() || !EnsureNotificationIcon()) {
    return false;
  }

  NOTIFYICONDATAW icon_data{};
  icon_data.cbSize = sizeof(icon_data);
  icon_data.hWnd = window_handle_;
  icon_data.uID = kNotificationIconId;
  // NIF_INFO requests the Windows alert. NIF_REALTIME discards it if Windows
  // cannot present it immediately instead of placing it in the display queue.
  icon_data.uFlags = NIF_INFO | NIF_REALTIME;
  icon_data.dwInfoFlags = NIIF_INFO;

  // Copy the fixed title into Windows' fixed-size notification-title buffer.
  wcsncpy_s(
      icon_data.szInfoTitle,
      sizeof(icon_data.szInfoTitle) / sizeof(icon_data.szInfoTitle[0]),
      kNotificationTitle,
      _TRUNCATE);

  // Copy the Dart-provided message into the notification body buffer,
  // truncating it safely if it exceeds Windows' available space.
  wcsncpy_s(
      icon_data.szInfo,
      sizeof(icon_data.szInfo) / sizeof(icon_data.szInfo[0]),
      notification_text.c_str(),
      _TRUNCATE);

  // Updating the registered icon with NIF_INFO asks Windows to show the alert.
  return Shell_NotifyIconW(NIM_MODIFY, &icon_data) != FALSE;
}

// The icon exists only to support notifications and is removed when analytics
// stops or when the plugin is destroyed.
void AnalyticsPlugin::RemoveNotificationIcon() {
  if (!notification_icon_added_) {
    return;
  }

  NOTIFYICONDATAW icon_data{};
  icon_data.cbSize = sizeof(icon_data);
  icon_data.hWnd = window_handle_;
  icon_data.uID = kNotificationIconId;

  // Unregister the icon so it does not remain in the taskbar after the session.
  Shell_NotifyIconW(NIM_DELETE, &icon_data);
  notification_icon_added_ = false;
}

void AnalyticsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == kIsSupportedMethod) {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method_call.method_name() == kStartSessionMethod) {
    if (session_active_) {
      result->Success();
      return;
    }

    session_active_ = true;
    result->Success();
    return;
  }

  if (method_call.method_name() == kStopSessionMethod) {
    if (!session_active_) {
      result->Success();
      return;
    }

    session_active_ = false;
    RemoveNotificationIcon();
    result->Success();
    return;
  }

  if (method_call.method_name() == kShowNotificationMethod) {
    // Dart decides when to notify and sends only the final message text.
    // Native code validates it and delegates its presentation to Windows.
    if (!session_active_) {
      result->Error(
          "session_inactive",
          "A notification cannot be shown outside an active session.");
      return;
    }

    const auto* arguments = method_call.arguments();

    if (arguments == nullptr ||
        !std::holds_alternative<std::string>(*arguments)) {
      result->Error(
          "invalid_notification_text",
          "Notification text must be a string.");
      return;
    }

    const std::string& notification_text =
        std::get<std::string>(*arguments);

    if (notification_text.empty()) {
      result->Error(
          "invalid_notification_text",
          "Notification text cannot be empty.");
      return;
    }

    if (!ShowNotification(notification_text)) {
      result->Error(
          "notification_failed",
          "Windows could not display the notification.");
      return;
    }

    result->Success();
    return;
  }

  if (method_call.method_name() == kGetForegroundActivityMethod) {
    if (!session_active_) {
      result->Success();
      return;
    }

    const ForegroundActivity activity = GetForegroundActivity();

    if (activity.application_name.empty()) {
      result->Success();
      return;
    }

    flutter::EncodableMap activity_result;
    activity_result[flutter::EncodableValue(kApplicationNameKey)] =
        flutter::EncodableValue(activity.application_name);
    activity_result[flutter::EncodableValue(kWindowTitleKey)] =
        activity.window_title.empty()
            ? flutter::EncodableValue()
            : flutter::EncodableValue(activity.window_title);

    result->Success(flutter::EncodableValue(activity_result));
    return;
  }

  result->NotImplemented();
}

}  // namespace analytics_plugin
