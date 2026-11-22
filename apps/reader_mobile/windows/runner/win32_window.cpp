#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// 启用深色窗口装饰的窗口属性。
///
/// 为使用早于 10.0.22000.0 版本 Windows SDK 的开发环境补充此定义。
/// 参见：https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

constexpr const wchar_t kWindowPlacementRegKey[] =
    L"Software\\Spectacular\\Reader";
constexpr const wchar_t kWindowPlacementRegValue[] = L"WindowPlacement";

// 当前存活的 Win32Window 对象数量。
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// 按传入的缩放比例，将逻辑尺寸转换为物理尺寸。
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// 从 User32 模块动态加载 |EnableNonClientDpiScaling|。
// 此接口仅用于 PerMonitor V1 感知模式。
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // 命名空间

// 管理 Win32Window 的窗口类注册。
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // 返回注册器的单例实例。
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // 返回窗口类名；尚未注册时先完成注册。
  const wchar_t* GetWindowClass();

  // 注销窗口类；仅可在不存在窗口实例时调用。
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTitleBar(window);
  RestorePlacement();

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, show_command_);
}

void Win32Window::RestorePlacement() {
  WINDOWPLACEMENT placement{};
  DWORD bytes = sizeof(placement);
  if (RegGetValueW(HKEY_CURRENT_USER, kWindowPlacementRegKey,
                   kWindowPlacementRegValue, RRF_RT_REG_BINARY, nullptr,
                   &placement, &bytes) != ERROR_SUCCESS ||
      bytes != sizeof(placement) || placement.length != sizeof(placement) ||
      placement.rcNormalPosition.right <= placement.rcNormalPosition.left ||
      placement.rcNormalPosition.bottom <= placement.rcNormalPosition.top) {
    return;
  }
  const UINT command = placement.showCmd == SW_SHOWMAXIMIZED
                           ? SW_SHOWMAXIMIZED
                           : SW_SHOWNORMAL;
  placement.flags = 0;
  placement.showCmd = SW_HIDE;
  if (SetWindowPlacement(window_handle_, &placement)) {
    show_command_ = command;
  }
}

void Win32Window::SavePlacement() {
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window_handle_, &placement)) return;
  placement.flags = 0;
  // 最小化时仍保存最近的普通或最大化状态，使用普通窗口矩形恢复大小。
  placement.showCmd = show_command_;
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowPlacementRegKey, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, kWindowPlacementRegValue, 0, REG_BINARY,
                 reinterpret_cast<const BYTE*>(&placement), sizeof(placement));
  RegCloseKey(key);
}

// 静态成员
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      SavePlacement();
      break;

    case WM_EXITSIZEMOVE:
      SavePlacement();
      return 0;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      if (wparam != SIZE_MINIMIZED) {
        show_command_ =
            wparam == SIZE_MAXIMIZED ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
      }
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // 设置子窗口的尺寸和位置。
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
    case WM_SETTINGCHANGE:
    case WM_SYSCOLORCHANGE:
      UpdateTitleBar(hwnd);
      break;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // 默认不执行操作，供子类重写。
  return true;
}

void Win32Window::OnDestroy() {
  // 默认不执行操作，供子类重写。
}

void Win32Window::SetTitleBarDarkMode(bool dark) {
  dark_title_bar_ = dark;
  UpdateTitleBar(window_handle_);
  RedrawWindow(window_handle_, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
}

void Win32Window::UpdateTitleBar(HWND const window) {
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  const bool use_system_colors =
      SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
      (contrast.dwFlags & HCF_HIGHCONTRASTON);
  const BOOL enable_dark_mode = dark_title_bar_ && !use_system_colors;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &enable_dark_mode, sizeof(enable_dark_mode));
  constexpr DWORD kCaptionColorAttribute = 35;
  constexpr DWORD kTextColorAttribute = 36;
  constexpr COLORREF kSystemColor = 0xFFFFFFFFu;
  const COLORREF caption = enable_dark_mode ? RGB(27, 29, 31) : RGB(246, 246, 244);
  const COLORREF text = enable_dark_mode ? RGB(231, 232, 228) : RGB(34, 36, 39);
  const COLORREF caption_color = use_system_colors ? kSystemColor : caption;
  const COLORREF text_color = use_system_colors ? kSystemColor : text;
  DwmSetWindowAttribute(window, kCaptionColorAttribute, &caption_color,
                        sizeof(caption_color));
  DwmSetWindowAttribute(window, kTextColorAttribute, &text_color,
                        sizeof(text_color));
}
