#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kDownloadMessage = WM_APP + 21;

std::wstring DownloadText(const flutter::EncodableMap& args, const char* key) {
  const auto found = args.find(flutter::EncodableValue(key));
  if (found == args.end()) return L"";
  const auto* text = std::get_if<std::string>(&found->second);
  if (!text || text->empty()) return L"";
  const int size = MultiByteToWideChar(CP_UTF8, 0, text->data(),
                                     static_cast<int>(text->size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text->data(), static_cast<int>(text->size()),
                      result.data(), size);
  return result;
}

int DownloadNumber(const flutter::EncodableMap& args, const char* key) {
  const auto found = args.find(flutter::EncodableValue(key));
  if (found == args.end()) return 0;
  const auto* number = std::get_if<int32_t>(&found->second);
  return number ? *number : 0;
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // 此处尺寸必须与窗口一致，避免启动时重复创建和销毁渲染表面。
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // 确认控制器的基本初始化成功。
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterAppearanceChannel();
  RegisterDownloadChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter 可能在注册显示窗口回调前完成首帧。以下调用确保仍有待绘制帧，
  // 从而显示窗口；若首帧尚未完成，此调用不执行额外操作。
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterAppearanceChannel() {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      flutter_controller_->engine()->messenger(),
      "com.spectacular.reader_mobile/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setDarkMode") {
      if (const auto* dark = std::get_if<bool>(call.arguments())) {
        SetWindowDarkMode(*dark);
        result->Success();
      } else {
        result->Error("invalid_argument");
      }
    } else if (call.method_name() == "setReaderWindowMode") {
      if (const auto* reading = std::get_if<bool>(call.arguments())) {
        SetReaderWindowMode(*reading);
        result->Success();
      } else {
        result->Error("invalid_argument");
      }
    } else {
      result->NotImplemented();
    }
  });
}

void FlutterWindow::RegisterDownloadChannel() {
  download_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.spectacular.reader_mobile/online_download",
          &flutter::StandardMethodCodec::GetInstance());
  download_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "update") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("invalid_argument");
      return;
    }
    const UINT id = DownloadNumber(*args, "id");
    const auto done_value = args->find(flutter::EncodableValue("done"));
    const bool done = done_value != args->end() &&
                      std::holds_alternative<bool>(done_value->second) &&
                      std::get<bool>(done_value->second);
    const auto title = DownloadText(*args, "title");
    auto message = DownloadText(*args, "message");
    const int total = DownloadNumber(*args, "total");
    if (!done && total > 0) {
      message += L" (" + std::to_wstring(DownloadNumber(*args, "completed")) +
                 L"/" + std::to_wstring(total) + L")";
    }
    const bool first = download_notifications_.find(id) ==
                       download_notifications_.end();
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = GetHandle();
    data.uID = id;
    data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    data.uCallbackMessage = kDownloadMessage;
    data.hIcon = LoadIcon(GetModuleHandle(nullptr),
                         MAKEINTRESOURCE(IDI_APP_ICON));
    wcsncpy_s(data.szTip, (title + L"： " + message).c_str(), _TRUNCATE);
    // 开始与结束显示系统通知，进行中在通知区提示里持续更新，避免反复弹出。
    if (first || done) {
      data.uFlags |= NIF_INFO;
      data.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
      wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
      wcsncpy_s(data.szInfo, message.c_str(), _TRUNCATE);
    }
    Shell_NotifyIconW(first ? NIM_ADD : NIM_MODIFY, &data);
    download_notifications_[id] = done;
    result->Success();
  });
}

void FlutterWindow::OnDestroy() {
  for (const auto& entry : download_notifications_) {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = GetHandle();
    data.uID = entry.first;
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
  download_notifications_.clear();
  download_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 先交由 Flutter 及其插件处理窗口消息。
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kDownloadMessage: {
      const UINT id = static_cast<UINT>(wparam);
      if (lparam == WM_LBUTTONUP || lparam == NIN_BALLOONUSERCLICK) {
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
      } else if (lparam == WM_RBUTTONUP) {
        const auto task = download_notifications_.find(id);
        if (task == download_notifications_.end()) return 0;
        POINT point{};
        GetCursorPos(&point);
        HMENU menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, 1, task->second ? L"关闭通知" : L"取消下载");
        SetForegroundWindow(hwnd);
        const UINT choice = TrackPopupMenu(
            menu, TPM_RETURNCMD | TPM_NONOTIFY, point.x, point.y, 0, hwnd, nullptr);
        DestroyMenu(menu);
        if (choice == 1) {
          if (!task->second) {
            download_channel_->InvokeMethod(
                "cancel", std::make_unique<flutter::EncodableValue>(
                              static_cast<int32_t>(id)));
          } else {
            NOTIFYICONDATAW data{};
            data.cbSize = sizeof(data);
            data.hWnd = hwnd;
            data.uID = id;
            Shell_NotifyIconW(NIM_DELETE, &data);
            download_notifications_.erase(id);
          }
        }
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
