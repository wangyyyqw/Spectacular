import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/text/font_coverage.dart';
import 'package:reader_core/text/font_digest.dart';
import 'package:reader_core/text/font_metrics.dart';

import '../library/library_store.dart';

export '../library/library_store.dart' show ReaderFontEntry;

/// 字体复制到应用目录，用内容摘要隔离引擎字体并支持重启恢复。
class ReaderFontStore {
  ReaderFontStore(
    this._library, {
    Future<Directory> Function()? directoryProvider,
    Future<PlatformFile?> Function()? picker,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _picker = picker ?? _pickFile;

  static const int maxBytes = 50 * 1024 * 1024;
  static final Map<String, Future<void>> _registrations = {};

  final LibraryStore _library;
  final Future<Directory> Function() _directoryProvider;
  final Future<PlatformFile?> Function() _picker;

  Future<Directory> _directory() async =>
      Directory(p.join((await _directoryProvider()).path, 'reader_fonts'));

  static Future<PlatformFile?> _pickFile() => FilePicker.pickFile(
    dialogTitle: '导入自定义字体',
    type: FileType.custom,
    allowedExtensions: ['ttf', 'otf'],
  );

  Future<List<ReaderFontEntry>> list() => _library.listUserFonts();

  /// 取消选择不保存，也不改变当前字体。
  Future<ReaderFontEntry?> pick() async {
    final file = await _picker();
    if (file == null) return null;
    final size = await file.length();
    if (size != null) _checkSize(size);
    return import(await file.readAsBytes(), displayName: file.name);
  }

  /// 校验完整字体表目录后保存，损坏文件不会进入字体清单。
  Future<ReaderFontEntry> import(
    Uint8List bytes, {
    required String displayName,
  }) async {
    _validate(bytes);
    // 中文字库可能有数十 MB，摘要计算放到工作 isolate 避免卡住界面。
    final family = 'user_${await compute(fontDigest, bytes)}';
    final entries = await list();
    final existing = entries.where((font) => font.family == family).firstOrNull;
    final directory = await _directory();
    await directory.create(recursive: true);
    final extension = ByteData.sublistView(bytes).getUint32(0) == 0x4F54544F
        ? 'otf'
        : 'ttf';
    final path = p.join(directory.path, '$family.$extension');
    final file = File(path);
    final hadFile = await file.exists();
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _register(family, bytes);
      final font = ReaderFontEntry(
        family: family,
        filePath: path,
        displayName: existing?.displayName ?? _displayName(displayName),
      );
      await _library.saveUserFont(font);
      return font;
    } catch (_) {
      if (!hadFile && await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// 恢复时再次检查内容摘要，外部替换或缺失字体会明确降级。
  Future<ReaderFontEntry> load(String family) async {
    if (!RegExp(r'^user_[0-9a-f]{64}$').hasMatch(family)) {
      throw const FormatException('自定义字体标识无效');
    }
    final entries = await list();
    final font = entries.where((entry) => entry.family == family).firstOrNull;
    if (font == null) throw const FormatException('自定义字体未导入');
    final directory = await _directory();
    if (!p.isWithin(p.normalize(directory.path), p.normalize(font.filePath))) {
      throw const FormatException('自定义字体路径无效');
    }
    final file = File(font.filePath);
    if (!await file.exists()) throw const FormatException('自定义字体文件已丢失');
    _checkSize(await file.length());
    final bytes = await file.readAsBytes();
    _validate(bytes);
    if ('user_${await compute(fontDigest, bytes)}' != family) {
      throw const FormatException('自定义字体文件已改变，请重新导入');
    }
    await _register(family, bytes);
    return font;
  }

  static String _displayName(String name) {
    final value = p.basenameWithoutExtension(name).trim();
    return value.isEmpty ? '自定义字体' : value;
  }

  static void _checkSize(int size) {
    if (size <= 0 || size > maxBytes) {
      throw const FormatException('请选择小于 50MB 的 TTF 或 OTF 字体');
    }
  }

  static void _validate(Uint8List bytes) {
    _checkSize(bytes.length);
    if (!_hasValidTables(bytes) || FontCoverage.parse(bytes) == null) {
      throw const FormatException('字体文件无效，请选择完整的 TTF 或 OTF 字体');
    }
  }

  static bool _hasValidTables(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final data = ByteData.sublistView(bytes);
    final version = data.getUint32(0);
    if (version != 0x00010000 &&
        version != 0x74727565 &&
        version != 0x4F54544F) {
      return false;
    }
    final count = data.getUint16(4);
    final directoryEnd = 12 + count * 16;
    if (count == 0 || directoryEnd > bytes.length) return false;
    final tables = <int>{};
    for (var i = 0; i < count; i++) {
      final record = 12 + i * 16;
      final offset = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      if (offset < directoryEnd || offset + length > bytes.length) return false;
      tables.add(data.getUint32(record));
    }
    const required = {
      0x68656164,
      0x6D617870,
      0x68686561,
      0x686D7478,
      0x636D6170,
    };
    if (!tables.containsAll(required)) return false;
    return version == 0x4F54544F
        ? tables.contains(0x43464620) || tables.contains(0x43464632)
        : tables.containsAll({0x676C7966, 0x6C6F6361});
  }

  static Future<void> _register(String family, Uint8List bytes) {
    return _registrations.putIfAbsent(family, () async {
      try {
        final loader = FontLoader(family);
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        final metrics = FontMetrics.parse(bytes);
        if (metrics != null) FontMetricsRegistry.register(family, metrics);
        final coverage = FontCoverage.parse(bytes);
        if (coverage != null) FontCoverageRegistry.register(family, coverage);
      } catch (_) {
        unawaited(_registrations.remove(family));
        throw const FormatException('自定义字体无法加载，请尝试其他字体');
      }
    });
  }
}
