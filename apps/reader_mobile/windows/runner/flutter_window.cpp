#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
    if (call.method_name() != "setDarkMode") {
      result->NotImplemented();
    } else if (const auto* dark = std::get_if<bool>(call.arguments())) {
      SetTitleBarDarkMode(*dark);
      result->Success();
    } else {
      result->Error("invalid_argument");
    }
  });
}

void FlutterWindow::OnDestroy() {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
