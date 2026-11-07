/// 轻量正文字符数统计（技术方案 §22.3）。
///
/// 导入期只需字符长度做进度权重与搜索索引，不做完整解析：去掉注释、
/// script/style 内容与标签，解码常见实体，再统计非空白字符。
abstract final class TextLengthScanner {
  static final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');
  static final RegExp _script = RegExp(
    r'<script\b[^>]*>[\s\S]*?</script>',
    caseSensitive: false,
  );
  static final RegExp _style = RegExp(
    r'<style\b[^>]*>[\s\S]*?</style>',
    caseSensitive: false,
  );
  static final RegExp _tag = RegExp(r'<[^>]*>');
  static final RegExp _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

  /// 统计 XHTML 片段的正文字符数（UTF-16 code unit，与 CFI 偏移同口径）。
  static int count(String xhtml) {
    if (xhtml.isEmpty) {
      return 0;
    }
    var text = xhtml
        .replaceAll(_comment, '')
        .replaceAll(_script, '')
        .replaceAll(_style, '');
    text = text.replaceAll(_tag, '');
    text = text.replaceAllMapped(_entity, _decodeEntity);
    var count = 0;
    for (var index = 0; index < text.length; index++) {
      if (!_isWhitespace(text.codeUnitAt(index))) {
        count += 1;
      }
    }
    return count;
  }

  /// 统计已聚合正文中的非空白字符数（UTF-16 code unit，与 CFI 同口径）。
  ///
  /// 旧书刷新字符统计时使用聚合后的正文，而不是原始 XHTML 正则去标签，
  /// 这样 CDATA、行内块提升等文本语义与阅读位置使用同一套坐标。
  static int countPlainText(String text) {
    var count = 0;
    for (var index = 0; index < text.length; index++) {
      if (!_isWhitespace(text.codeUnitAt(index))) count += 1;
    }
    return count;
  }

  /// 返回第 [target] 个非空白字符之后的原文偏移。
  ///
  /// 用于把字符权重进度反向映射到 CFI：跳过空白字符，保留 UTF-16 代码
  /// 单元偏移语义。目标为 0 时返回 0，超出总数时返回文本长度。
  static int offsetForPlainTextCount(String text, int target) {
    if (target <= 0) return 0;
    var count = 0;
    for (var index = 0; index < text.length; index++) {
      if (_isWhitespace(text.codeUnitAt(index))) continue;
      count += 1;
      if (count == target) return index + 1;
    }
    return text.length;
  }

  // 保持 Dart RegExp 的 \s 集合，避免逐码元创建字符串并运行正则。
  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x0020 ||
      (codeUnit >= 0x0009 && codeUnit <= 0x000d) ||
      codeUnit == 0x00a0 ||
      codeUnit == 0x1680 ||
      (codeUnit >= 0x2000 && codeUnit <= 0x200a) ||
      codeUnit == 0x2028 ||
      codeUnit == 0x2029 ||
      codeUnit == 0x202f ||
      codeUnit == 0x205f ||
      codeUnit == 0x3000 ||
      codeUnit == 0xfeff;

  static String _decodeEntity(Match match) {
    final body = match.group(1) ?? '';
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final code = int.tryParse(body.substring(2), radix: 16);
      return code == null ? ' ' : String.fromCharCode(code);
    }
    if (body.startsWith('#')) {
      final code = int.tryParse(body.substring(1));
      return code == null ? ' ' : String.fromCharCode(code);
    }
    return switch (body) {
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      'nbsp' => ' ',
      'emsp' || 'ensp' || 'thinsp' => ' ',
      _ => ' ',
    };
  }
}
