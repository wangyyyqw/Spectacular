import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dict_reader/dict_reader.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../library/library_store.dart';

class LocalDictionaryException implements Exception {
  const LocalDictionaryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalDictionaryEntry {
  const LocalDictionaryEntry({
    required this.id,
    required this.name,
    required this.digest,
    required this.wordCount,
    this.mddFiles = const [],
    this.cssFiles = const [],
    this.enabled = true,
  });

  final String id, name, digest;
  final int wordCount;
  final List<String> mddFiles, cssFiles;
  final bool enabled;

  LocalDictionaryEntry withEnabled(bool value) => LocalDictionaryEntry(
    id: id,
    name: name,
    digest: digest,
    wordCount: wordCount,
    mddFiles: mddFiles,
    cssFiles: cssFiles,
    enabled: value,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'digest': digest,
    'wordCount': wordCount,
    'mddFiles': mddFiles,
    'cssFiles': cssFiles,
    'enabled': enabled,
  };

  factory LocalDictionaryEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final mddFiles = (json['mddFiles'] as List).cast<String>();
    final cssFiles = (json['cssFiles'] as List).cast<String>();
    if (!RegExp(r'^local-[a-zA-Z0-9-]+$').hasMatch(id) ||
        [
          ...mddFiles,
          ...cssFiles,
        ].any((name) => name != p.basename(name) || name.contains('\\'))) {
      throw const FormatException('本地词典配置无效');
    }
    return LocalDictionaryEntry(
      id: id,
      name: json['name'] as String,
      digest: json['digest'] as String,
      wordCount: json['wordCount'] as int,
      mddFiles: mddFiles,
      cssFiles: cssFiles,
      enabled: json['enabled'] != false,
    );
  }
}

/// 词库和索引只保存在本机，不修改书库数据库结构或同步内容。
class LocalDictionaryStore {
  LocalDictionaryStore(this.library, {this.directoryProvider});
  final LibraryStore library;
  final Future<Directory> Function()? directoryProvider;
  static const settingKey = 'dictionary.local.v1';
  static final _queues = Expando<Future<void>>();
  bool get canImport =>
      library.supportsPersistence || directoryProvider != null;

  Future<Directory> _root() async {
    if (!canImport) {
      throw const LocalDictionaryException('当前为临时模式，无法保存本地词典');
    }
    final support =
        await (directoryProvider ?? getApplicationSupportDirectory)();
    return Directory(p.join(support.path, 'dictionaries'));
  }

  Future<List<LocalDictionaryEntry>> load() async {
    await _queues[library];
    return _read();
  }

  Future<List<LocalDictionaryEntry>> _read() async {
    final raw = await library.getSetting(settingKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (item) => LocalDictionaryEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<T> _update<T>(Future<T> Function() action) {
    final task = (_queues[library] ?? Future<void>.value()).then(
      (_) => action(),
    );
    _queues[library] = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> _save(List<LocalDictionaryEntry> entries) => library.setSetting(
    settingKey,
    jsonEncode(entries.map((entry) => entry.toJson()).toList()),
  );

  Future<void> setEnabled(String id, bool enabled) => _update(() async {
    final entries = await _read();
    await _save([
      for (final entry in entries)
        entry.id == id ? entry.withEnabled(enabled) : entry,
    ]);
  });

  Future<void> remove(String id) => _update(() async {
    final entries = await _read();
    final entry = entries.where((entry) => entry.id == id).firstOrNull;
    if (entry == null) return;
    final directory = Directory(p.join((await _root()).path, entry.id));
    // 先提交清单；文件删除失败不把已经失效的词库继续提供给查询。
    await _save(entries.where((entry) => entry.id != id).toList());
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<LocalDictionaryEntry> importFiles(List<String> paths) => _update(
    () async {
      final files = paths.toSet().toList();
      final mdx = files.where(
        (path) => p.extension(path).toLowerCase() == '.mdx',
      );
      if (mdx.length != 1) {
        throw const LocalDictionaryException('每次请选择一个 MDX，可同时选择同名 MDD 分卷和 CSS');
      }
      final stem = RegExp.escape(p.basenameWithoutExtension(mdx.single));
      final mddPattern = RegExp(
        '^$stem(?:\\.\\d+)?\\.mdd\$',
        caseSensitive: false,
      );
      if (files.any((path) {
        final ext = p.extension(path).toLowerCase();
        return !['.mdx', '.mdd', '.css'].contains(ext) ||
            (ext == '.mdd' && !mddPattern.hasMatch(p.basename(path)));
      })) {
        throw const LocalDictionaryException(
          '只支持 MDX、同名 MDD（含 .1.mdd 分卷）及 CSS 文件',
        );
      }
      if (files.map((path) => p.basename(path).toLowerCase()).toSet().length !=
          files.length) {
        throw const LocalDictionaryException('所选文件存在重名，请只选择同一套词库文件');
      }
      final digest = (await sha256.bind(File(mdx.single).openRead()).first)
          .toString();
      final entries = await _read();
      if (entries.any((entry) => entry.digest == digest)) {
        throw const LocalDictionaryException('该词典已导入；更新配套资源请先移除后重新导入');
      }
      final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
      final directory = Directory(p.join((await _root()).path, id));
      try {
        final entry = await _prepareInBackground(
          directory.path,
          id,
          digest,
          files,
          mdx.single,
        );
        await _save([...entries, entry]);
        return entry;
      } catch (error) {
        if (await directory.exists()) await directory.delete(recursive: true);
        throw localDictionaryError(error);
      }
    },
  ).catchError((Object error) => throw localDictionaryError(error));

  Future<LocalDictionarySession> open(LocalDictionaryEntry entry) async {
    final directory = Directory(p.join((await _root()).path, entry.id));
    final session = LocalDictionarySession(entry, directory);
    try {
      await session._open();
      return session;
    } catch (error) {
      await session.close();
      throw localDictionaryError(error);
    }
  }
}

// 独立闭包只传递文件参数，不能把宿主的数据库连接带入后台 isolate。
Future<LocalDictionaryEntry> _prepareInBackground(
  String directory,
  String id,
  String digest,
  List<String> paths,
  String mdx,
) => Isolate.run(() => _prepareDictionary(directory, id, digest, paths, mdx));

Future<LocalDictionaryEntry> _prepareDictionary(
  String directory,
  String id,
  String digest,
  List<String> paths,
  String mdx,
) async {
  await Directory(directory).create(recursive: true);
  await File(mdx).copy(p.join(directory, 'dictionary.mdx'));
  final info = await _buildIndex(p.join(directory, 'dictionary.mdx'));
  final mddFiles = <String>[];
  final cssFiles = <String>[];
  for (final source in paths.where((path) => path != mdx)) {
    final name = p.basename(source);
    if (p.extension(name).toLowerCase() == '.mdd') {
      await File(source).copy(p.join(directory, name));
      await _buildIndex(p.join(directory, name));
      mddFiles.add(name);
    } else {
      await Directory(p.join(directory, 'styles')).create();
      await File(source).copy(p.join(directory, 'styles', name));
      cssFiles.add(name);
    }
  }
  return LocalDictionaryEntry(
    id: id,
    name: info.$1.isEmpty ? p.basenameWithoutExtension(mdx) : info.$1,
    digest: digest,
    wordCount: info.$2,
    mddFiles: mddFiles
      ..sort((a, b) {
        int volume(String name) =>
            int.tryParse(
              RegExp(
                    r'\.(\d+)\.mdd$',
                    caseSensitive: false,
                  ).firstMatch(name)?.group(1) ??
                  '0',
            ) ??
            0;
        return volume(a).compareTo(volume(b));
      }),
    cssFiles: cssFiles,
  );
}

Future<(String, int)> _buildIndex(String path) async {
  final reader = DictReader(path);
  try {
    await reader.initDict(readKeys: false, readRecordBlockInfo: false);
    final version = double.tryParse(
      reader.header['GeneratedByEngineVersion'] ?? '',
    );
    final encrypted = reader.header['Encrypted'];
    if (version == null || version >= 3) {
      throw const LocalDictionaryException('暂不支持 MDict 3.0，请使用 1.x / 2.x 词库');
    }
    if (encrypted == 'Yes' || ((int.tryParse(encrypted ?? '') ?? 0) & 1) != 0) {
      throw const LocalDictionaryException('暂不支持记录块加密词库');
    }
    await reader.initDict(readHeader: false);
    if (reader.wordCount == 0) {
      throw const LocalDictionaryException('词库没有可用词条');
    }
    final first = await reader.locate(reader.wordAt(0));
    if (first != null) await reader.readRecordData(first);
    await File('$path.cidx')
        .writeAsBytes(await reader.exportCidx(), flush: true);
    return (
      html.parseFragment(reader.title).text?.trim() ?? '',
      reader.wordCount,
    );
  } finally {
    await reader.close();
  }
}

LocalDictionaryException localDictionaryError(Object error) {
  if (error is LocalDictionaryException) return error;
  if (error is UnsupportedCompressionException) {
    return const LocalDictionaryException('暂不支持 LZO 等压缩方式，请使用未压缩或 zlib 压缩词库');
  }
  if (error is FileSystemException) {
    return const LocalDictionaryException('词库文件无法读取，请检查存储空间或重新导入');
  }
  return const LocalDictionaryException(
    '词库损坏或格式不受支持，请使用有效的 MDX/MDD 1.x / 2.x 文件',
  );
}

class LocalDictionarySession {
  LocalDictionarySession(this.entry, this.directory);
  final LocalDictionaryEntry entry;
  final Directory directory;
  late DictReader _mdx;
  final _readers = <DictReader>[];
  final _resources = <DictReader>[];
  Future<void> _resourceReads = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;

  Future<DictReader> _reader(String name) async {
    final path = p.join(directory.path, name);
    final reader = DictReader(path);
    _readers.add(reader);
    try {
      await reader.importCidx(await File('$path.cidx').readAsBytes());
    } on FormatException {
      // 索引可重建，源词库不改写；旧版或失效索引不阻断离线查询。
      await _buildIndex(path);
      await reader.importCidx(await File('$path.cidx').readAsBytes());
    } on PathNotFoundException {
      await _buildIndex(path);
      await reader.importCidx(await File('$path.cidx').readAsBytes());
    }
    return reader;
  }

  Future<void> _open() async {
    _mdx = await _reader('dictionary.mdx');
    // MDD 只在实际请求资源时打开，纯文本查询不加载图片或音频索引。
  }

  List<String> suggest(String text) => _mdx.search(text.trim(), limit: 8);

  Future<String?> lookup(String text) async {
    try {
      return await _lookup(text.trim(), <String>{});
    } catch (error) {
      throw localDictionaryError(error);
    }
  }

  Future<String?> _lookup(String word, Set<String> visited) async {
    if (word.isEmpty) return null;
    if (!visited.add(word) || visited.length > 16) {
      throw const LocalDictionaryException('词条跳转循环，无法读取释义');
    }
    var entries = await _mdx.lookup(word);
    if (entries.isEmpty && word != word.toLowerCase()) {
      entries = await _mdx.lookup(word.toLowerCase());
    }
    if (entries.isEmpty) return null;
    final definitions = <String>[];
    for (final entry in entries) {
      final value = (await entry.readText()).replaceAll('\u0000', '').trim();
      if (value.startsWith('@@@LINK=')) {
        final target = value.substring(8).trim();
        final linked = await _lookup(target, {...visited});
        if (linked != null) definitions.add(linked);
      } else if (value.isNotEmpty) {
        definitions.add(value);
      }
    }
    return definitions.isEmpty ? null : definitions.join('<hr>');
  }

  Future<Uint8List?> resource(String path) {
    if (_closed) return Future.value();
    final task = _resourceReads.then((_) => _resource(path));
    _resourceReads = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<Uint8List?> _resource(String path) async {
    if (path.isEmpty ||
        path.contains('\u0000') ||
        path.split(RegExp(r'[/\\]')).any((part) => part == '..')) {
      return null;
    }
    if (entry.cssFiles.contains(path)) {
      return File(p.join(directory.path, 'styles', path)).readAsBytes();
    }
    // 按需打开分卷；同一会话复用二进制索引和解析库的块缓存。
    for (var index = 0; index < entry.mddFiles.length; index++) {
      if (_resources.length <= index) {
        _resources.add(await _reader(entry.mddFiles[index]));
      }
      final bytes = await _resources[index].getResource(path);
      if (bytes != null) return bytes;
    }
    return null;
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _resourceReads;
    for (final reader in _readers) {
      await reader.close();
    }
    _readers.clear();
    _resources.clear();
  }
}
