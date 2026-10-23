/// EPUB 解析错误：带稳定错误码，供 [ImportReport] 与 UI 使用。
class EpubException implements Exception {
  /// 创建错误。
  const EpubException(this.code, this.message);

  /// 稳定错误码（大写下划线）。
  final String code;

  /// 可读原因。
  final String message;

  @override
  String toString() => 'EpubException($code): $message';
}
