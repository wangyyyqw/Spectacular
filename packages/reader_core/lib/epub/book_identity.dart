import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 跨设备书籍标识的固定算法；修改规则必须另建版本，不能改变既有 ID。
///
/// 使用 EPUB 原始书名、作者和 unique-identifier，去除首尾空白后按
/// UTF-8 JSON 数组编码。缺失标识固定为空，不使用文件名、时间或随机数。
/// 返回 SHA-256 前 128 位，即 32 个小写十六进制字符。
String generateBookId({
  required String title,
  required String author,
  required String identifier,
}) {
  final payload = jsonEncode([
    'spectacular-book-id-v1',
    title.trim(),
    author.trim(),
    identifier.trim(),
  ]);
  return sha256.convert(utf8.encode(payload)).toString().substring(0, 32);
}
