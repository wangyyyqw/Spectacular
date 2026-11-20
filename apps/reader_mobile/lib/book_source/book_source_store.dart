import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_source_models.dart';

/// 书源与书架在线关联的本地存储。
class BookSourceStore {
  BookSourceStore({
    Future<Directory> Function()? directoryProvider,
    http.Client? client,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _client = client ?? http.Client();

  static const int maxSourceBytes = 8 * 1024 * 1024;

  final Future<Directory> Function() _directoryProvider;
  final http.Client _client;
  List<BookSource>? _cache;
  Map<String, OnlineBookLink>? _links;

  /// 读取全部书源；损坏的配置文件不会静默覆盖。
  Future<List<BookSource>> load({bool refresh = false}) async {
    if (!refresh && _cache != null) {
      return List<BookSource>.unmodifiable(_cache!);
    }
    final data = await _readConfig();
    final rawSources = data['sources'];
    final loaded = <BookSource>[];
    if (rawSources is List) {
      for (final value in rawSources) {
        final json = _jsonObject(value);
        if (json == null) continue;
        try {
          loaded.add(BookSource.fromJson(json));
        } on Object {
          // 单个坏条目不应阻断其他书源。
        }
      }
    }
    loaded.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    _cache = loaded;
    _links = <String, OnlineBookLink>{
      for (final entry
          in (data['links'] as Map? ?? const <Object?, Object?>{}).entries)
        if (entry.key is String)
          entry.key as String: OnlineBookLink.fromJson(
            _jsonObject(entry.value) ?? const <String, Object?>{},
          ),
    };
    return List<BookSource>.unmodifiable(loaded);
  }

  /// 从 JSON 文本导入一个书源。
  Future<BookSource> importText(String rawText) async {
    final bytes = Uint8List.fromList(utf8.encode(rawText));
    return importBytes(bytes);
  }

  /// 从文件导入一个书源。
  Future<BookSource> importFile(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length <= 0) {
      throw const BookSourceException('书源文件为空');
    }
    if (length > maxSourceBytes) {
      throw const BookSourceException('书源文件过大');
    }
    return importBytes(await file.readAsBytes());
  }

  /// 从网络地址导入一个书源。
  Future<BookSource> importUrl(String rawUrl) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority) {
      throw const BookSourceException('请输入 HTTP(S) 书源地址');
    }
    final response = await _client
        .get(uri, headers: const <String, String>{'Accept': '*/*'})
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BookSourceException('下载书源失败（HTTP ${response.statusCode}）');
    }
    if (response.bodyBytes.length > maxSourceBytes) {
      throw const BookSourceException('书源文件过大');
    }
    return importBytes(response.bodyBytes);
  }

  /// 从字节导入；兼容 JSON、单元素数组与内嵌 JSON 的压缩包。
  Future<BookSource> importBytes(Uint8List bytes) async {
    if (bytes.isEmpty) throw const BookSourceException('书源内容为空');
    if (bytes.length > maxSourceBytes) {
      throw const BookSourceException('书源文件过大');
    }
    final json = _decodeSourceJson(bytes);
    final parsed = BookSource.fromJson(json);
    _validate(parsed);
    final sources = await load(refresh: true);
    final existing = sources.where(
      (source) =>
          source.id == parsed.id ||
          (source.sourceUrl.isNotBlank &&
              source.sourceUrl.toLowerCase() == parsed.sourceUrl.toLowerCase()),
    );
    final previous = existing.isEmpty ? null : existing.first;
    final incoming = parsed.copyWith(
      id: previous?.id,
      enabled: previous?.enabled ?? parsed.enabled,
    );
    final next =
        <BookSource>[
          for (final source in sources)
            if (source.id != incoming.id) source,
          incoming,
        ]..sort(
          (left, right) =>
              left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        );
    _cache = next;
    await _writeConfig();
    return incoming;
  }

  /// 启用或停用书源。
  Future<void> setEnabled(String id, bool enabled) =>
      _update(id, (source) => source.copyWith(enabled: enabled));

  Future<void> setLoadMode(String id, BookSourceLoadMode mode) =>
      _update(id, (source) => source.copyWith(loadMode: mode));

  Future<void> _update(
    String id,
    BookSource Function(BookSource) change,
  ) async {
    final sources = await load();
    final next = <BookSource>[
      for (final source in sources)
        if (source.id == id) change(source) else source,
    ];
    if (!next.any((source) => source.id == id)) {
      throw const BookSourceException('书源不存在');
    }
    _cache = next;
    await _writeConfig();
  }

  /// 删除书源。
  Future<void> remove(String id) async {
    final sources = await load();
    final next = sources.where((source) => source.id != id).toList();
    if (next.length == sources.length) return;
    _cache = next;
    final links = Map<String, OnlineBookLink>.of(await loadLinks());
    links.removeWhere((_, link) => link.sourceId == id);
    _links = links;
    await _writeConfig();
  }

  /// 读取书架书籍与在线来源的关联。
  Future<Map<String, OnlineBookLink>> loadLinks() async {
    if (_links == null) await load();
    return Map<String, OnlineBookLink>.unmodifiable(
      _links ?? const <String, OnlineBookLink>{},
    );
  }

  /// 记录一本书的在线来源。
  Future<void> saveLink(String bookId, OnlineBookLink link) async {
    if (bookId.trim().isEmpty) return;
    final links = Map<String, OnlineBookLink>.of(await loadLinks());
    links[bookId] = link.copyWith(updatedAt: DateTime.now());
    _links = links;
    await _writeConfig();
  }

  /// 移除书架书籍的在线来源。
  Future<void> removeLink(String bookId) async {
    final links = Map<String, OnlineBookLink>.of(await loadLinks());
    if (links.remove(bookId) == null) return;
    _links = links;
    await _writeConfig();
  }

  void dispose() => _client.close();

  Map<String, Object?> _decodeSourceJson(Uint8List bytes) {
    if (_looksLikeZip(bytes)) {
      return _sourceFromArchive(bytes);
    }
    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceFirst('\ufeff', '')
        .trim();
    if (text.isEmpty) throw const BookSourceException('书源内容为空');
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        if (decoded.isEmpty) {
          throw const BookSourceException('书源列表为空');
        }
        if (decoded.length != 1) {
          throw const BookSourceException('一次最多导入一个书源');
        }
        final item = _jsonObject(decoded.first);
        if (item == null) throw const BookSourceException('书源格式不正确');
        return item;
      }
      final item = _jsonObject(decoded);
      if (item == null) throw const BookSourceException('书源格式不正确');
      return item;
    } on FormatException {
      throw const BookSourceException('书源不是有效的 JSON');
    }
  }

  Map<String, Object?> _sourceFromArchive(Uint8List bytes) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const BookSourceException('无法读取书源压缩包');
    }
    for (final file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.json')) continue;
      if (file.size > 512 * 1024) continue;
      final content = file.content;
      final text = utf8.decode(content, allowMalformed: true).trim();
      if (!text.contains('bookSource') && !text.contains('ruleSearch')) {
        continue;
      }
      try {
        final decoded = jsonDecode(text);
        final object = _jsonObject(decoded);
        if (object != null) return object;
      } on FormatException {
        continue;
      }
    }
    throw const BookSourceException('该压缩书源只包含编译代码，当前版本无法直接执行；请导入 JSON 书源');
  }

  bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;

  void _validate(BookSource source) {
    if (source.type != 0) {
      throw const BookSourceException('当前只支持文本类书源');
    }
    final uri = Uri.tryParse(source.sourceUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority) {
      throw const BookSourceException('书源站点地址无效');
    }
    if (source.searchUrl.isBlank) {
      throw const BookSourceException('书源缺少搜索地址');
    }
    if (source.search.bookList.isBlank) {
      throw const BookSourceException('书源缺少搜索结果列表规则');
    }
    if (source.toc.chapterList.isBlank) {
      throw const BookSourceException('书源缺少目录列表规则');
    }
    if (source.content.content.isBlank) {
      throw const BookSourceException('书源缺少正文规则');
    }
  }

  Future<Map<String, Object?>> _readConfig() async {
    final file = await _configFile();
    final source = await file.exists() ? file : File('${file.path}.bak');
    if (!await source.exists()) return <String, Object?>{};
    try {
      final decoded = jsonDecode(await source.readAsString());
      return _jsonObject(decoded) ?? <String, Object?>{};
    } on FormatException {
      throw const BookSourceException('书源配置文件已损坏，请先备份再清理');
    } on FileSystemException catch (error) {
      throw BookSourceException('读取书源配置失败：${error.message}');
    }
  }

  Future<void> _writeConfig() async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    final data = <String, Object?>{
      'version': 1,
      'sources': <Object?>[
        for (final source in _cache ?? const <BookSource>[]) source.toJson(),
      ],
      'links': <String, Object?>{
        for (final entry
            in (_links ?? const <String, OnlineBookLink>{}).entries)
          entry.key: entry.value.toJson(),
      },
    };
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    if (!await file.exists()) {
      await temp.rename(file.path);
      return;
    }
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<File> _configFile() async {
    final root = await _directoryProvider();
    return File(p.join(root.path, 'book_sources', 'sources.json'));
  }
}

Map<String, Object?>? _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}

extension _BlankString on String {
  bool get isNotBlank => trim().isNotEmpty;

  bool get isBlank => trim().isEmpty;
}
