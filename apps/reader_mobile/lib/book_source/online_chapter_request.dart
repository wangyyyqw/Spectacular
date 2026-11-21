import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_models.dart';

/// 章节地址与请求选项共同标识正文，同一接口的不同 POST 正文彼此独立。
String onlineChapterIdentity(OnlineChapter chapter) =>
    onlineRequestIdentity(chapter.url, chapter.requestOptions);

/// 兼容旧目录中尚未拆出的 data URL 选项，显式选项优先。
({String url, Map<String, Object?> options}) onlineChapterRequest(
  OnlineChapter chapter,
) {
  final request = splitBookSourceUrlOptions(chapter.url);
  return (
    url: request.url,
    options: {...request.options, ...chapter.requestOptions},
  );
}

/// 忽略网络链接片段与对象字段顺序；data 内容保持完整。
String onlineRequestIdentity(String url, Map<String, Object?> options) {
  final request = splitBookSourceUrlOptions(url);
  final raw = request.url;
  final uri = Uri.tryParse(raw);
  final normalizedUrl = raw.toLowerCase().startsWith('data:')
      ? raw
      : uri?.removeFragment().normalizePath().toString() ?? raw;
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            normalizedUrl,
            _normalizeOptions({...request.options, ...options}),
          ]),
        ),
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
