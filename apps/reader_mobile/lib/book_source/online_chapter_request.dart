import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_models.dart';

/// 章节地址与请求选项共同标识正文，同一接口的不同 POST 正文彼此独立。
String onlineChapterIdentity(OnlineChapter chapter) =>
    onlineRequestIdentity(chapter.url, chapter.requestOptions);

/// 忽略链接片段与对象字段顺序，保留查询参数和列表顺序。
String onlineRequestIdentity(String url, Map<String, Object?> options) {
  final raw = url.trim();
  final uri = Uri.tryParse(raw);
  final normalizedUrl = uri?.removeFragment().normalizePath().toString() ?? raw;
  return sha256
      .convert(
        utf8.encode(jsonEncode([normalizedUrl, _normalizeOptions(options)])),
      )
      .toString();
}

Object? _normalizeOptions(Object? value) {
  if (value is Map) {
    final keys = value.keys.whereType<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _normalizeOptions(value[key]),
    };
  }
  if (value is List) return [for (final item in value) _normalizeOptions(item)];
  return value;
}
