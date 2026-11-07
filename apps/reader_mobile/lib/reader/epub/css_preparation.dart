import 'dart:typed_data';

import 'package:reader_core/css/parser.dart';
import 'package:reader_core/epub/xml_encoding.dart';

/// worker 只接收 CSS 文本或字节，不捕获书籍归档与字体注册器。
CssStylesheet parseCssText(String css) => CssParser.parse(css);

CssStylesheet parseCssBytes(Uint8List? bytes) => bytes == null
    ? const CssStylesheet(rules: [], imports: [], warnings: [])
    : parseCssText(decodeTextBytes(bytes));
