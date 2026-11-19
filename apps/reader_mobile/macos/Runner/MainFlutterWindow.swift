import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    self.appearance = NSAppearance(named: .aqua)
    self.titlebarSeparatorStyle = .none

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
      guard call.method == "setDarkMode" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let dark = call.arguments as? Bool else {
        // 跟随系统时解除窗口外观覆盖，让系统亮度继续传入 Flutter。
        if call.arguments == nil || call.arguments is NSNull {
          self?.appearance = nil
          result(nil)
          return
        }
        result(FlutterError(code: "invalid_argument", message: nil, details: nil))
        return
      }
      self?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      result(nil)
    }

    super.awakeFromNib()
  }
}
