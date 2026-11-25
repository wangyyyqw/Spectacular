import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let darkBackground = NSColor(
    srgbRed: 34.0 / 255.0,
    green: 36.0 / 255.0,
    blue: 39.0 / 255.0,
    alpha: 1
  )

  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    self.appearance = NSAppearance(named: .aqua)
    self.titlebarSeparatorStyle = .none
    // 标题栏融入内容：隐藏标题文字，保留左上角红绿灯。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.isOpaque = true
    self.backgroundColor = .white

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 使用系统偏好保存窗口尺寸和位置，并在下次启动时恢复。
    let autosaveName = "spectacular-main-window"
    self.setFrameUsingName(autosaveName)
    self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let appearanceChannel = FlutterMethodChannel(
      name: "com.spectacular.reader_mobile/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appearanceChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setDarkMode":
        guard let dark = call.arguments as? Bool else {
          // 跟随系统时解除窗口外观覆盖，让系统亮度继续传入 Flutter。
          if call.arguments == nil || call.arguments is NSNull {
            self?.appearance = nil
            self?.updateWindowBackground()
            result(nil)
            return
          }
          result(FlutterError(code: "invalid_argument", message: nil, details: nil))
          return
        }
        self?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        self?.backgroundColor = dark ? Self.darkBackground : .white
        result(nil)
      case "getWindowInsets":
        result(self?.windowInsets ?? ["top": 0.0])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.windowChannel = appearanceChannel
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowFullScreenChanged(_:)),
      name: NSWindow.didEnterFullScreenNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowFullScreenChanged(_:)),
      name: NSWindow.didExitFullScreenNotification,
      object: self
    )

    super.awakeFromNib()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private var windowInsets: [String: Any] {
    // 标准窗口标题栏高度；全屏时红绿灯隐藏，不再占用顶部空间。
    let top = styleMask.contains(.fullScreen) ? 0.0 : 28.0
    return ["top": top]
  }

  private func updateWindowBackground() {
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
      == .darkAqua
    backgroundColor = dark ? Self.darkBackground : .white
  }

  @objc private func windowFullScreenChanged(_ notification: Notification) {
    windowChannel?.invokeMethod("windowInsetsChanged", arguments: windowInsets)
  }
}
