/// OPF 整页图片与多看跨页图属性。
class OpfPageFlags {
  /// 创建页属性。
  const OpfPageFlags({
    this.fullScreen = false,
    this.fitWindow = false,
    this.spreadLeft = false,
    this.spreadRight = false,
  });

  /// 未标记任何页属性。
  static const OpfPageFlags none = OpfPageFlags();

  /// 整页显示（`duokan-page-fullscreen` 及其跨页变体）。
  final bool fullScreen;

  /// 整页图窗口内适配、上下居中（`duokan-page-fitwindow`）。
  final bool fitWindow;

  /// 全屏图保留左侧（`duokan-page-fullscreen-spread-left`）。
  final bool spreadLeft;

  /// 全屏图保留右侧（`duokan-page-fullscreen-spread-right`）。
  final bool spreadRight;

  /// 是否走整页图路径（全屏或窗口适配）。
  bool get isFullPage => fullScreen || fitWindow;

  @override
  String toString() =>
      'OpfPageFlags(fullScreen: $fullScreen, fitWindow: $fitWindow, '
      'spreadLeft: $spreadLeft, spreadRight: $spreadRight)';
}
