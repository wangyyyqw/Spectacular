#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <map>
#include <flutter/method_channel.h>

#include "win32_window.h"

// 仅用于承载 Flutter 视图的窗口。
class FlutterWindow : public Win32Window {
 public:
  // 创建 FlutterWindow，承载运行 |project| 的 Flutter 视图。
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window 重写方法：
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RegisterAppearanceChannel();
  void RegisterDownloadChannel();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> download_channel_;
  std::map<UINT, bool> download_notifications_;

  // 要运行的项目。
  flutter::DartProject project_;

  // 当前窗口承载的 Flutter 实例。
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
