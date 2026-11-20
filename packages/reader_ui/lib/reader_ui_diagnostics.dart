/// 阅读器 UI 的诊断回调桥接，由宿主应用写入自己的日志系统。
class ReaderUiDiagnostics {
  ReaderUiDiagnostics._();

  /// 宿主提供的事件接收器；未配置时保持静默。
  static void Function(String event, Map<String, Object?> fields)? onEvent;

  /// 记录 UI 事件或已处理异常，不直接向用户显示提示。
  static void record(
    String event, {
    String? message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    onEvent?.call(event, <String, Object?>{
      ...?message == null ? null : <String, Object?>{'message': message},
      ...?error == null ? null : <String, Object?>{'error': error},
      ...?stackTrace == null ? null : <String, Object?>{'stack': stackTrace},
    });
  }
}
