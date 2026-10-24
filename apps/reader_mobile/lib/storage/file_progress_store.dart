import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader_ui/reader_session.dart';

/// 把阅读进度持久化到应用支持目录的 JSON 文件。
/// [FileReaderProgressStore.memory] 为纯内存模式（无 IO，测试用）。
class FileReaderProgressStore implements ReaderProgressStore {
  /// 创建存储；[directoryProvider] 供测试注入。
  FileReaderProgressStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// 纯内存模式：不触文件系统（widget 测试用）。
  FileReaderProgressStore.memory() : _directoryProvider = null;

  final Future<Directory> Function()? _directoryProvider;
  Future<void>? _loading;
  final Map<String, ReaderProgress> _items = <String, ReaderProgress>{};
  File? _file;

  bool get _isMemory => _directoryProvider == null;

  Future<void> _ensureLoaded() {
    if (_isMemory) {
      return Future<void>.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final directory = await _directoryProvider!();
      await directory.create(recursive: true);
      _file = File('${directory.path}/reader_progress.json');
      if (!await _file!.exists()) {
        return;
      }
      final text = await _file!.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }
        final spine = value['spine'];
        final page = value['page'];
        if (spine is int && page is int) {
          _items[entry.key] = ReaderProgress(
            spineIndex: spine,
            pageIndex: page,
          );
        }
      }
    } catch (_) {
      // 存储不可用时退回内存；不阻塞阅读。
    }
  }

  @override
  Future<ReaderProgress?> load(String bookId) async {
    await _ensureLoaded();
    return _items[bookId];
  }

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    await _ensureLoaded();
    _items[bookId] = progress;
    await _persist();
  }

  /// 清除某书的进度（删书时调用）。
  Future<void> clear(String bookId) async {
    await _ensureLoaded();
    if (_items.remove(bookId) == null) {
      return;
    }
    await _persist();
  }

  /// 全部已存进度（统计页用；键为 bookId）。
  Future<Map<String, ReaderProgress>> snapshot() async {
    await _ensureLoaded();
    return Map<String, ReaderProgress>.unmodifiable(_items);
  }

  Future<void> _persist() async {
    if (_isMemory) {
      return;
    }
    final file = _file;
    if (file == null) {
      return;
    }
    try {
      final data = <String, Object?>{
        for (final entry in _items.entries)
          entry.key: <String, Object?>{
            'spine': entry.value.spineIndex,
            'page': entry.value.pageIndex,
          },
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 写失败不影响翻页。
    }
  }
}
