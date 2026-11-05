import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 字体内容摘要，用于稳定注册与重复导入去重。
String fontDigest(Uint8List bytes) => sha256.convert(bytes).toString();
