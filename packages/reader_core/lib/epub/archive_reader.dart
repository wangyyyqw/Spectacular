import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_exception.dart';

/// OCF 校验结果。
class OcfReport {
  /// 创建校验结果。
  const OcfReport({required this.errors, required this.warnings});

  /// 致命问题。
  final List<String> errors;

  /// 可恢复问题（例如真实书籍的 mimetype 被压缩）。
  final List<String> warnings;

  /// 是否通过（无致命问题）。
  bool get ok => errors.isEmpty;
}

/// EPUB 的 ZIP 容器读取与 OCF 校验。
class EpubArchive {
  EpubArchive._(this._entries, this._orderedNames, this.diagnostics);

  /// 从字节打开 ZIP；损坏时按四档分类（P7-15），可恢复档先修复再抛：
  ///
  /// 1. **条目截断/损坏**（CRC 失败）→ 降级重解码，坏条目跳过并记
  ///    `E_ZIP_ENTRY_TRUNCATED` 诊断，其余条目照常可用；
  /// 2. **局部头错位**（中心目录偏移指向错误位置）→ 扫描真实局部头、
  ///    修补偏移后重解码，记 `E_ZIP_LOCAL_HEADER` 诊断；
  /// 3. **EOCD/中心目录缺失** → `E_ZIP_EOCD_MISSING`（不可恢复）；
  /// 4. **文件名传统编码错位** → `E_ZIP_NAME_ENCODING`（资源索引按
  ///    大小写与字节匹配兜底；GBK 重解码待自研 ZIP 层，见 §54）。
  ///
  /// 其余失败保持 [EpubException]（E_ARCHIVE/E_CRC）。
  factory EpubArchive.fromBytes(Uint8List bytes) {
    List<ArchiveFile> files;
    try {
      files = ZipDecoder().decodeBytes(bytes, verify: true).files;
    } catch (error) {
      // 第一层恢复：不做 CRC 校验重解码（覆盖整档 verify 抛出，
      // 坏条目由 [_build] 逐条跳过）。
      try {
        files = ZipDecoder().decodeBytes(bytes, verify: false).files;
      } catch (_) {
        // 第二层恢复：局部头偏移修补（zipLocalHeaderRelocated 场景）。
        final repaired = _repairLocalHeaderOffsets(bytes);
        if (repaired != null) {
          try {
            files = ZipDecoder().decodeBytes(repaired, verify: true).files;
            return _build(files, diagnostics: const <String>[
              'E_ZIP_LOCAL_HEADER: 局部头偏移错位，已扫描修补中心目录并恢复',
            ]);
          } catch (_) {
            // 修补后仍失败：落到分类抛出。
          }
        }
        throw _classifyZipError(error);
      }
    }
    // 本版 package:archive 对局部头错位会「静默丢条目」：解码成功但
    // 条目变成空名零长占位——按「有名字段目」数少于中心目录触发修补
    // 重解码（P7-15）。
    final recovered = _recoverDroppedEntries(bytes, files);
    if (recovered != null) {
      return _build(recovered, diagnostics: const <String>[
        'E_ZIP_LOCAL_HEADER: 解码丢失条目，已按局部头扫描修补恢复',
      ]);
    }
    return _build(files, diagnostics: const <String>[]);
  }

  /// 静默丢条目的恢复：有名字段目数少于中心目录时修补偏移重解码，
  /// 取回更多有名字段目则返回；无可恢复返回 null。
  static List<ArchiveFile>? _recoverDroppedEntries(
    Uint8List bytes,
    List<ArchiveFile> decoded,
  ) {
    final centralCount = _centralEntryCount(bytes);
    final namedCount = decoded
        .where((file) => file.isFile && file.name.trim().isNotEmpty)
        .length;
    if (centralCount == null || centralCount <= namedCount) {
      return null;
    }
    final repaired = _repairLocalHeaderOffsets(bytes);
    if (repaired == null) {
      return null;
    }
    try {
      final files = ZipDecoder().decodeBytes(repaired, verify: true).files;
      return files.where((file) => file.isFile && file.name.trim().isNotEmpty).length >
              namedCount
          ? files
          : null;
    } catch (_) {
      return null;
    }
  }

  /// 中心目录条目数（EOCD +10）；EOCD 缺失或 zip64 返回 null。
  static int? _centralEntryCount(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    if (eocd == null) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final count = data.getUint16(eocd + 10, Endian.little);
    // zip64 标记位：0xFFFF 视为不可信。
    return count == 0xFFFF ? null : count;
  }

  /// 组装条目表；单条 CRC 失败记诊断跳过（截断档恢复）。全部条目
  /// 损坏抛 `E_ZIP_ENTRY_TRUNCATED`，真空 ZIP 抛 `E_ARCHIVE`。
  static EpubArchive _build(
    List<ArchiveFile> files, {
    required List<String> diagnostics,
  }) {
    final entries = <String, ArchiveFile>{};
    final order = <String>[];
    final notes = <String>[...diagnostics];
    var corrupted = 0;
    for (final file in files) {
      if (!file.isFile) {
        continue;
      }
      if (file.crc32 != null) {
        final actual = getCrc32(file.content);
        if (actual != file.crc32) {
          corrupted += 1;
          notes.add(
            'E_ZIP_ENTRY_TRUNCATED: 条目 ${file.name} 损坏（CRC 不符），已跳过',
          );
          continue;
        }
      }
      final name = _normalizePath(file.name);
      if (name.isEmpty || file.isDirectory) {
        // 解码器对局部头错位会产出「空名零长」占位条目：修复失败时
        // 在此留痕，不让丢条目完全静默（P7-15）。
        if (name.isEmpty && file.isFile) {
          notes.add(
            'E_ZIP_LOCAL_HEADER: 检测到无法定位的条目（局部头错位），已跳过',
          );
        }
        continue;
      }
      entries[name] = file;
      order.add(name);
    }
    if (entries.isEmpty) {
      if (corrupted > 0) {
        throw const EpubException(
          'E_ZIP_ENTRY_TRUNCATED',
          '全部条目均损坏，无法恢复',
        );
      }
      throw const EpubException('E_ARCHIVE', 'ZIP 中没有文件');
    }
    return EpubArchive._(entries, order, List<String>.unmodifiable(notes));
  }

  /// 把解码异常归类到 ZIP 四档（P7-15）。
  static EpubException _classifyZipError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('crc') || message.contains('checksum')) {
      return EpubException('E_CRC', 'CRC 校验失败：$error');
    }
    if (message.contains('end of central directory') ||
        message.contains('eocd') ||
        message.contains('central directory')) {
      return const EpubException(
        'E_ZIP_EOCD_MISSING',
        'EOCD/中心目录缺失，无法恢复',
      );
    }
    if (message.contains('local file header') ||
        message.contains('local header') ||
        message.contains('invalid header')) {
      return const EpubException(
        'E_ZIP_LOCAL_HEADER',
        '局部头损坏/错位，修补未成功',
      );
    }
    if (message.contains('encoding') || message.contains('filename')) {
      return EpubException('E_ZIP_NAME_ENCODING', '文件名编码错位：$error');
    }
    if (message.contains('truncate') ||
        message.contains('unexpected end') ||
        message.contains('eof')) {
      return const EpubException('E_ZIP_ENTRY_TRUNCATED', '条目截断');
    }
    return EpubException('E_ARCHIVE', 'ZIP 解析失败：$error');
  }

  /// 局部头偏移修补：按 EOCD 定位中心目录，逐条目校验局部头签名与
  /// 文件名；错位者在邻域扫描真实局部头（签名 + 同名）并回写偏移。
  /// 任一条目无法定位返回 null。仅处理 32 位偏移（zip64 不修）。
  static Uint8List? _repairLocalHeaderOffsets(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    if (eocd == null) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final entryCount = data.getUint16(eocd + 10, Endian.little);
    var cursor = data.getUint32(eocd + 16, Endian.little);
    final cdStart = cursor;
    final patched = Uint8List.fromList(bytes);
    final patchedView = ByteData.sublistView(patched);
    for (var i = 0; i < entryCount; i++) {
      if (cursor + 46 > bytes.length ||
          data.getUint32(cursor, Endian.little) != 0x02014b50) {
        return null;
      }
      final nameLength = data.getUint16(cursor + 28, Endian.little);
      final extraLength = data.getUint16(cursor + 30, Endian.little);
      final commentLength = data.getUint16(cursor + 32, Endian.little);
      final localOffset = data.getUint32(cursor + 42, Endian.little);
      final nameBytes = bytes.sublist(
        cursor + 46,
        cursor + 46 + nameLength,
      );
      final repaired = _locateLocalHeader(
        bytes,
        expectedOffset: localOffset,
        nameBytes: nameBytes,
        searchLimit: cdStart,
      );
      if (repaired == null) {
        return null;
      }
      if (repaired != localOffset) {
        patchedView.setUint32(cursor + 42, repaired, Endian.little);
      }
      cursor += 46 + nameLength + extraLength + commentLength;
    }
    return patched;
  }

  /// EOCD 签名（PK\x05\x06）位置；从尾部向前扫 64KB。
  static int? _findEocd(Uint8List bytes) {
    final start = bytes.length > 66000 ? bytes.length - 66000 : 0;
    final data = ByteData.sublistView(bytes);
    for (var i = bytes.length - 22; i >= start; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50) {
        return i;
      }
    }
    return null;
  }

  /// 在记录偏移处校验局部头（签名 + 同名）；失败则向前 4KB、向后
  /// 64KB 扫描同名局部头。命中返回真实偏移，未命中返回 null。
  static int? _locateLocalHeader(
    Uint8List bytes, {
    required int expectedOffset,
    required List<int> nameBytes,
    required int searchLimit,
  }) {
    bool validAt(int offset) {
      if (offset < 0 || offset + 30 > bytes.length) {
        return false;
      }
      final data = ByteData.sublistView(bytes);
      if (data.getUint32(offset, Endian.little) != 0x04034b50) {
        return false;
      }
      final nameLength = data.getUint16(offset + 26, Endian.little);
      if (nameLength != nameBytes.length) {
        return false;
      }
      for (var i = 0; i < nameBytes.length; i++) {
        if (bytes[offset + 30 + i] != nameBytes[i]) {
          return false;
        }
      }
      return true;
    }

    if (validAt(expectedOffset)) {
      return expectedOffset;
    }
    final back = expectedOffset - 4096 < 0 ? 0 : expectedOffset - 4096;
    final forwardLimit =
        expectedOffset + 65536 > searchLimit
        ? searchLimit
        : expectedOffset + 65536;
    for (var offset = back; offset + 30 <= forwardLimit; offset++) {
      if (validAt(offset)) {
        return offset;
      }
    }
    return null;
  }

  final Map<String, ArchiveFile> _entries;
  final List<String> _orderedNames;

  /// 打开期诊断（恢复档的记录，供 ImportReport 汇总）。
  final List<String> diagnostics;

  /// 全部文件名（保持 ZIP 顺序）。
  List<String> get names => List<String>.unmodifiable(_orderedNames);

  /// 文件数。
  int get length => _entries.length;

  /// 是否存在指定路径。
  bool contains(String path) => _entries.containsKey(_normalizePath(path));

  /// 读取字节；不存在返回 null。
  Uint8List? readBytes(String path) {
    final entry = _entries[_normalizePath(path)];
    if (entry == null) {
      return null;
    }
    return Uint8List.fromList(entry.content);
  }

  /// 读取文本（UTF-8）；不存在返回 null。
  String? readString(String path) {
    final bytes = readBytes(path);
    if (bytes == null) {
      return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 条目的压缩方式；不存在返回 null。
  CompressionType? compressionOf(String path) =>
      _entries[_normalizePath(path)]?.compression;

  /// 校验 OCF 的 mimetype 约定。
  OcfReport validateOcf() {
    final errors = <String>[];
    final warnings = <String>[];

    if (_orderedNames.isEmpty) {
      return OcfReport(errors: <String>['ZIP 为空'], warnings: warnings);
    }
    if (_orderedNames.first != 'mimetype') {
      errors.add('mimetype 不是第一个条目（实际：${_orderedNames.first}）');
    }

    final mimetype = _entries['mimetype'];
    if (mimetype == null) {
      return OcfReport(errors: <String>['缺少 mimetype 条目'], warnings: warnings);
    }

    final value = utf8.decode(mimetype.content, allowMalformed: true).trim();
    if (value != 'application/epub+zip') {
      errors.add('mimetype 内容错误：$value');
    }
    if (mimetype.compression != CompressionType.none) {
      warnings.add(
        'mimetype 被压缩（${mimetype.compression?.name ?? 'unknown'}），不符合 OCF',
      );
    }
    return OcfReport(errors: errors, warnings: warnings);
  }

  static String _normalizePath(String path) {
    var result = path.replaceAll('\\', '/');
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return result;
  }
}
