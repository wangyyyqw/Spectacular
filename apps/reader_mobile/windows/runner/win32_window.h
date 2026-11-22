#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// 支持高 DPI 的 Win32 窗口抽象，供需要自定义渲染和输入处理的子类继承。
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // 在默认显示器上创建标题为 |title| 的窗口，以 |origin| 和 |size| 定位并设置大小。
  // 操作系统采用物理像素，此函数会按默认显示器缩放输入尺寸以保持显示大小一致。
  // 调用 |Show| 前窗口不可见；创建成功时返回 true。
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // 显示当前窗口；显示成功时返回 true。
  bool Show();

  // 释放窗口关联的操作系统资源。
  void Destroy();

  // 将 |content| 加入窗口树。
  void SetChildContent(HWND content);

  // 返回底层窗口句柄，供调用方设置图标等属性；窗口销毁后返回 nullptr。
  HWND GetHandle();

  // 为 true 时，关闭此窗口会退出应用。
  void SetQuitOnClose(bool quit_on_close);

  // 返回表示当前客户区边界的 RECT。
  RECT GetClientArea();

 protected:
  void SetTitleBarDarkMode(bool dark);

  // 处理并分发鼠标、尺寸变化和 DPI 相关窗口消息，委托给子类可重写的成员函数。
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // 创建窗口时调用，供子类完成窗口相关初始化；初始化失败时子类应返回 false。
  virtual bool OnCreate();

  // 调用 Destroy 时触发。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // 由消息循环调用的系统回调。在非客户区创建时处理 WM_NCCREATE，启用非客户区
  // 自动 DPI 缩放，使其响应 DPI 变化；其余消息由 MessageHandler 处理。
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // 获取 |window| 对应的类实例指针。
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  void UpdateTitleBar(HWND const window);

  // 在当前用户的应用偏好中保存、恢复窗口大小和显示状态。
  void RestorePlacement();
  void SavePlacement();

  bool quit_on_close_ = false;
  bool dark_title_bar_ = false;
  UINT show_command_ = SW_SHOWNORMAL;

  // 顶层窗口句柄。
  HWND window_handle_ = nullptr;

  // 承载内容的窗口句柄。
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
