import 'package:reader_core/css/parser.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/xml_encoding.dart';

/// worker 只接收 CSS 文本或字节，不捕获书籍归档与字体注册器。
CssStylesheet parseCssText(String css) => CssParser.parse(css);

/// 解压和解析共用一个 worker；失败诊断由归档所有者提交。
({CssStylesheet sheet, String? error}) parseCssEntry(EpubEntryPayload? input) {
  final decoded = input == null ? null : decodeEpubEntry(input);
  final bytes = decoded?.bytes;
  return (
    sheet: bytes == null
        ? const CssStylesheet(rules: [], imports: [], warnings: [])
        : parseCssText(decodeTextBytes(bytes)),
    error: decoded?.error,
  );
}
