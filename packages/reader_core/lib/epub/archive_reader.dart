import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_exception.dart';
import 'epub_entry.dart';
import 'epub_limits.dart';
import 'xml_encoding.dart';
import 'zip_source.dart';

export 'epub_entry.dart'
    show EpubEntryPayload, EpubEntryDecodeResult, decodeEpubEntry;
export 'epub_limits.dart' show EpubArchiveLimits;

/// 宿主独占的读取凭据；仅 [payload] 可交给纯数据 worker。
class EpubEntryRead {
  EpubEntryRead._(this._owner, this._path, this._identity, this.payload);

  final EpubArchive _owner;
  final String _path;
  final Object _identity;
  final EpubEntryPayload payload;
}

typedef _PreparedEntry = ({Object identity, EpubEntryPayload payload});

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
///
/// 默认走惰性索引：打开时只解析中央目录（几百 KB），条目在读取时才解压，
/// 且不保留解压结果。100MB+ 的书不再把整本字节和解压内容常驻内存。
///
/// ZIP64/加密/特殊压缩等变体回退到 `package:archive` 整本解码，保持既有
/// 兼容行为；这类归档在阅读路径上有大小上限，避免内存峰值失控。
class EpubArchive {
  EpubArchive._(this._backend, this._orderedNames, this._diagnostics);

  /// 为按需提供正文的文档保存共享资源，无需生成 ZIP。
  factory EpubArchive.fromResources(Map<String, Uint8List> resources) {
    final files = {
      for (final entry in resources.entries)
        _normalizePath(entry.key): ArchiveFile(
          _normalizePath(entry.key),
          entry.value.length,
          Uint8List.fromList(entry.value),
        ),
    };
    return EpubArchive._(
      _DecodedArchiveBackend(files),
      files.keys.toList(),
      [],
    );
  }

  /// 编辑预览持有独立覆盖快照；关闭时同时关闭传入的基础归档。
  factory EpubArchive.withOverrides(
    EpubArchive base,
    Map<String, Uint8List?> changes,
  ) {
    final snapshot = <String, Uint8List?>{
      for (final entry in changes.entries)
        _normalizePath(entry.key): entry.value == null
            ? null
            : Uint8List.fromList(entry.value!),
    };
    final names = <String>[
      for (final name in {...base.names, ...snapshot.keys})
        if (!snapshot.containsKey(name) || snapshot[name] != null) name,
    ];
    return EpubArchive._(
      _OverlayArchiveBackend(base, snapshot),
      names,
      List.of(base.diagnostics),
    );
  }

  final _ArchiveBackend _backend;
  final List<String> _orderedNames;
  final List<String> _diagnostics;

  /// 打开期诊断（恢复档的记录，供 ImportReport 汇总）。
  List<String> get diagnostics => List<String>.unmodifiable(_diagnostics);

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
  ///
  /// [verify] 为 false 时跳过 CRC 校验：大文件（150MB+）解码能快数倍，
  /// 阅读场景用（导入时已完整校验过一次）。
  factory EpubArchive.fromBytes(
    Uint8List bytes, {
    bool verify = true,
    EpubArchiveLimits limits = const EpubArchiveLimits(),
  }) {
    final index = ZipIndex.tryParse(
      ZipByteSource.fromBytes(bytes),
      validateHeaders: true,
      verifyCrc: verify,
      limits: limits,
    );
    if (index != null) {
      return _fromIndex(index, verify: verify);
    }
    return _decodeArchiveBytes(bytes, verify: verify, limits: limits);
  }

  /// 从文件打开：只解析中央目录，条目按需读取。
  ///
  /// 这是阅读路径的入口。内存占用只与中央目录和当前章节有关，不再随书
  /// 的体积线性增长。[verify] 为 true 时逐条解压校验 CRC（导入用，内存
  /// 有界但耗时）；阅读路径传 false——导入时已完整校验过一次。
  static Future<EpubArchive> fromFile(
    File file, {
    bool verify = false,
    EpubArchiveLimits limits = const EpubArchiveLimits(),
  }) async {
    final source = await ZipByteSource.fromFile(file);
    ZipIndex? index;
    try {
      index = ZipIndex.tryParse(
        source,
        validateHeaders: false,
        verifyCrc: verify,
        limits: limits,
      );
    } on EpubException {
      await source.close();
      rethrow;
    } catch (_) {
      index = null;
    }
    if (index != null) {
      try {
        return _fromIndex(index, verify: verify);
      } catch (_) {
        index.release();
        rethrow;
      }
    }
    await source.close();
    // 仅 ZIP64/加密/特殊编码等异常容器走整本兜底；正常 EPUB 不进入。
    if (await file.length() > limits.maxArchiveBytes) {
      throw const EpubException('E_ARCHIVE', '归档格式不受支持且文件过大，无法安全打开');
    }
    final bytes = await file.readAsBytes();
    return _decodeArchiveBytes(
      bytes,
      verify: verify,
      limits: limits,
      notes: const <String>['E_ZIP_LEGACY: 归档变体不受惰性读取支持，已整本解码'],
    );
  }

  static EpubArchive _fromIndex(
    ZipIndex index, {
    required bool verify,
    List<String> notes = const <String>[],
  }) {
    if (verify) {
      for (final name in List<String>.of(index.order)) {
        final entry = index.entries[name];
        if (entry != null) {
          index.verifyEntry(entry);
        }
      }
    }
    if (index.entries.isEmpty) {
      final truncated = index.diagnostics.any(
        (item) => item.startsWith('E_ZIP_ENTRY_TRUNCATED'),
      );
      throw EpubException(
        truncated ? 'E_ZIP_ENTRY_TRUNCATED' : 'E_ARCHIVE',
        truncated
            ? '全部条目均损坏，无法恢复'
            : index.diagnostics.isEmpty
            ? 'ZIP 中没有文件'
            : '归档没有可安全读取的条目',
      );
    }
    return EpubArchive._(
      _ZipIndexBackend(index),
      List<String>.of(index.order),
      List<String>.unmodifiable(<String>[...notes, ...index.diagnostics]),
    );
  }

  /// 整本解码路径：仅用于惰性层不支持的归档变体。
  static EpubArchive _decodeArchiveBytes(
    Uint8List bytes, {
    required bool verify,
    required EpubArchiveLimits limits,
    List<String> notes = const <String>[],
  }) {
    final decoded = _decodeWithRecovery(bytes, verify: verify, limits: limits);
    final recovered = _recoverDroppedEntries(
      bytes,
      decoded.files,
      verify: verify,
      limits: limits,
    );
    return _build(
      recovered ?? decoded.files,
      verify: verify,
      limits: limits,
      diagnostics: [
        ...notes,
        ...decoded.diagnostics,
        if (recovered != null) 'E_ZIP_LOCAL_HEADER: 解码丢失条目，已按局部头扫描修补恢复',
      ],
    );
  }

  static ({List<ArchiveFile> files, List<String> diagnostics})
  _decodeWithRecovery(
    Uint8List bytes, {
    required bool verify,
    required EpubArchiveLimits limits,
  }) {
    List<ArchiveFile> files;
    try {
      files = _decodeFiles(bytes, verify: verify, limits: limits);
    } on EpubException {
      rethrow;
    } catch (error) {
      // 第一层恢复：不做 CRC 校验重解码（覆盖整档 verify 抛出，
      // 坏条目由 [_build] 逐条跳过）。
      try {
        files = _decodeFiles(bytes, verify: false, limits: limits);
      } on EpubException {
        rethrow;
      } catch (_) {
        // 第二层恢复：局部头偏移修补（zipLocalHeaderRelocated 场景）。
        final repaired = _repairLocalHeaderOffsets(bytes);
        if (repaired != null) {
          try {
            files = _decodeFiles(repaired, verify: verify, limits: limits);
            return (
              files: files,
              diagnostics: ['E_ZIP_LOCAL_HEADER: 局部头偏移错位，已扫描修补中心目录并恢复'],
            );
          } on EpubException {
            rethrow;
          } catch (_) {
            // 修补后仍失败：落到分类抛出。
          }
        }
        throw _classifyZipError(error);
      }
    }
    return (files: files, diagnostics: []);
  }

  /// 先读取 ZIP64 等变体的元数据，再允许旧解码器接触内容和符号链接。
  static List<ArchiveFile> _decodeFiles(
    Uint8List bytes, {
    required bool verify,
    required EpubArchiveLimits limits,
  }) {
    if (bytes.length > limits.maxArchiveBytes) {
      throw const EpubException('E_ARCHIVE', '归档格式不受支持且文件过大，无法安全打开');
    }
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    final budget = EpubDecodeBudget(limits);
    for (final header in directory.fileHeaders) {
      final file = header.file!;
      final headerFailure = limits.entryFailure(
        header.filename,
        header.compressedSize,
        header.uncompressedSize,
      );
      if (headerFailure != null) {
        throw EpubException('E_ARCHIVE', headerFailure);
      }
      if (!budget.admit(
        file.filename,
        file.compressedSize,
        file.uncompressedSize,
      )) {
        throw EpubException('E_ARCHIVE', budget.diagnostics.last);
      }
    }
    return ZipDecoder().decodeBytes(bytes, verify: verify).files;
  }

  /// 静默丢条目的恢复：有名条目数少于中心目录时修补偏移重解码，
  /// 取回更多有名条目则返回；无可恢复返回 null。
  static List<ArchiveFile>? _recoverDroppedEntries(
    Uint8List bytes,
    List<ArchiveFile> decoded, {
    required bool verify,
    required EpubArchiveLimits limits,
  }) {
    final centralCount = _centralEntryCount(bytes);
    final namedCount = decoded
        .where((file) => file.name.trim().isNotEmpty)
        .length;
    if (centralCount == null || centralCount <= namedCount) {
      return null;
    }
    final repaired = _repairLocalHeaderOffsets(bytes);
    if (repaired == null) {
      return null;
    }
    try {
      final files = _decodeFiles(repaired, verify: verify, limits: limits);
      return files.where((file) => file.name.trim().isNotEmpty).length >
              namedCount
          ? files
          : null;
    } on EpubException {
      rethrow;
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

  /// 组装条目表；单条解压或 CRC 失败记诊断跳过（截断档恢复）。全部条目
  /// 损坏抛 `E_ZIP_ENTRY_TRUNCATED`，真空 ZIP 抛 `E_ARCHIVE`。
  /// 此函数保留单遍装配，避免诊断与条目顺序脱节；预算和损坏回归约束风险。
  static EpubArchive _build(
    List<ArchiveFile> files, {
    required bool verify,
    required EpubArchiveLimits limits,
    required List<String> diagnostics,
  }) {
    final entries = <String, ArchiveFile>{};
    final order = <String>[];
    final notes = <String>[...diagnostics];
    final budget = EpubDecodeBudget(limits);
    var corrupted = 0;
    for (final file in files) {
      if (!file.isFile) {
        continue;
      }
      if (!budget.admit(file.name, file.rawContent?.length ?? 0, file.size)) {
        notes.add(budget.diagnostics.last);
        continue;
      }
      final failure = verify ? _entryFailure(file) : null;
      if (failure != null) {
        corrupted += 1;
        notes.add('E_ZIP_ENTRY_TRUNCATED: 条目 ${file.name} 损坏（$failure），已跳过');
        continue;
      }
      final name = _normalizePath(file.name);
      if (name.isEmpty || file.isDirectory) {
        // 解码器对局部头错位会产出「空名零长」占位条目：修复失败时
        // 在此留痕，不让丢条目完全静默（P7-15）。
        if (name.isEmpty && file.isFile) {
          notes.add('E_ZIP_LOCAL_HEADER: 检测到无法定位的条目（局部头错位），已跳过');
        }
        continue;
      }
      entries[name] = file;
      order.add(name);
    }
    if (entries.isEmpty) {
      if (corrupted > 0) {
        throw const EpubException('E_ZIP_ENTRY_TRUNCATED', '全部条目均损坏，无法恢复');
      }
      throw const EpubException('E_ARCHIVE', 'ZIP 中没有文件');
    }
    return EpubArchive._(
      _DecodedArchiveBackend(entries),
      order,
      List<String>.unmodifiable({...notes, ...budget.diagnostics}),
    );
  }

  static String? _entryFailure(ArchiveFile file) {
    if (file.crc32 == null) {
      return null;
    }
    try {
      return getCrc32(file.content) == file.crc32 ? null : 'CRC 不符';
    } catch (error) {
      // archive 惰性解压；压缩流异常必须与 CRC 不符一样按条目隔离。
      return '解压失败：$error';
    }
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
      return const EpubException('E_ZIP_EOCD_MISSING', 'EOCD/中心目录缺失，无法恢复');
    }
    if (message.contains('local file header') ||
        message.contains('local header') ||
        message.contains('invalid header')) {
      return const EpubException('E_ZIP_LOCAL_HEADER', '局部头损坏/错位，修补未成功');
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
  /// 无需修补或任一条目无法定位返回 null。仅处理 32 位偏移（zip64 不修）。
  static Uint8List? _repairLocalHeaderOffsets(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    if (eocd == null) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final entryCount = data.getUint16(eocd + 10, Endian.little);
    var cursor = data.getUint32(eocd + 16, Endian.little);
    final cdStart = cursor;
    Uint8List? patched;
    for (var i = 0; i < entryCount; i++) {
      if (cursor + 46 > bytes.length ||
          data.getUint32(cursor, Endian.little) != 0x02014b50) {
        return null;
      }
      final nameLength = data.getUint16(cursor + 28, Endian.little);
      final extraLength = data.getUint16(cursor + 30, Endian.little);
      final commentLength = data.getUint16(cursor + 32, Endian.little);
      final localOffset = data.getUint32(cursor + 42, Endian.little);
      final nameBytes = bytes.sublist(cursor + 46, cursor + 46 + nameLength);
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
        patched ??= Uint8List.fromList(bytes);
        ByteData.sublistView(patched)
            .setUint32(cursor + 42, repaired, Endian.little);
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
    final forwardLimit = expectedOffset + 65536 > searchLimit
        ? searchLimit
        : expectedOffset + 65536;
    for (var offset = back; offset + 30 <= forwardLimit; offset++) {
      if (validAt(offset)) {
        return offset;
      }
    }
    return null;
  }

  /// 全部文件名（保持 ZIP 顺序）。
  List<String> get names => List<String>.unmodifiable(_orderedNames);

  /// 文件数。
  int get length => _backend.length;

  /// 释放所有条目持有的压缩字节与已解压缓存 / 文件句柄。
  ///
  /// 阅读页关闭后必须主动清空，否则大书或重复打开时内存会一直占用。
  /// 关闭后再次读取返回 null，调用方不应继续使用本归档。
  void close() {
    _backend.close();
    _orderedNames.clear();
  }

  /// 是否存在指定路径。
  bool contains(String path) => _backend.contains(_normalizePath(path));

  /// 条目的未压缩字节数；不存在或归档已关闭时返回 null。
  ///
  /// 只读取中央目录或旧后端已有的条目元数据，不读取、解压或解析内容。
  /// 阅读进度可据此准备全书权重，而无需扫描每章 XHTML。
  int? uncompressedSizeOf(String path) =>
      _backend.uncompressedSizeOf(_normalizePath(path));

  /// 读取字节；不存在返回 null。
  Uint8List? readBytes(String path) => _backend.readBytes(_normalizePath(path));

  /// 文件来源优先异步读取 ZIP 条目，避免打开阅读页时同步阻塞主 isolate。
  Future<Uint8List?> readBytesAsync(String path) async {
    final normalized = _normalizePath(path);
    final prepared = await _backend.prepareEntryAsync(normalized);
    if (prepared == null) return null;
    final decoded = decodeEpubEntry(prepared.payload);
    if (!_backend.commitEntry(normalized, prepared.identity, decoded.error)) {
      return null;
    }
    return decoded.bytes;
  }

  /// 准备单条完整输入，保留归档句柄与修复状态；旧后端仍在宿主解码。
  EpubEntryRead? prepareEntry(String path) {
    final normalized = _normalizePath(path);
    final prepared = _backend.prepareEntry(normalized);
    return prepared == null
        ? null
        : EpubEntryRead._(
            this,
            normalized,
            prepared.identity,
            prepared.payload,
          );
  }

  /// 文件后端异步读取完整压缩区间，供准备 worker 解压大图片。
  Future<EpubEntryRead?> prepareEntryAsync(String path) async {
    final normalized = _normalizePath(path);
    final prepared = await _backend.prepareEntryAsync(normalized);
    return prepared == null
        ? null
        : EpubEntryRead._(
            this,
            normalized,
            prepared.identity,
            prepared.payload,
          );
  }

  /// 提交纯数据解压状态；外来、已关闭或已移除条目的凭据返回 false。
  ///
  /// 宿主应先检查作业取消和版本，再调用本方法并发布解析产物。
  bool commitEntry(EpubEntryRead read, String? error) {
    if (!identical(read._owner, this)) return false;
    return _backend.commitEntry(read._path, read._identity, error);
  }

  /// 只读取条目开头至多 [maxBytes] 个解压字节；不存在返回 null。
  ///
  /// 供图片尺寸与媒体类型嗅探使用，避免为了文件头解压整张大图。
  Uint8List? readHead(String path, int maxBytes) =>
      _backend.readHead(_normalizePath(path), maxBytes);

  /// 读取 XML/XHTML 文本（UTF-8 或 UTF-16）；不存在返回 null。
  String? readString(String path) {
    final bytes = readBytes(path);
    if (bytes == null) {
      return null;
    }
    return decodeXmlBytes(bytes);
  }

  /// 条目的压缩方式；不存在返回 null。
  CompressionType? compressionOf(String path) =>
      _backend.compressionOf(_normalizePath(path));

  /// 校验 OCF 的 mimetype 约定。
  OcfReport validateOcf() {
    final errors = <String>[];
    final warnings = <String>[];

    if (_orderedNames.isEmpty) {
      return OcfReport(errors: <String>['ZIP 为空'], warnings: warnings);
    }

    if (_orderedNames.first != 'mimetype') {
      warnings.add('mimetype 不是第一个条目（实际：${_orderedNames.first}），不符合 OCF');
    }

    if (!_backend.contains('mimetype')) {
      return OcfReport(errors: <String>['缺少 mimetype 条目'], warnings: warnings);
    }

    final value = utf8
        .decode(
          _backend.readBytes('mimetype') ?? Uint8List(0),
          allowMalformed: true,
        )
        .trim();
    if (value != 'application/epub+zip') {
      errors.add('mimetype 内容错误：$value');
    }
    final compression = _backend.compressionOf('mimetype');
    if (compression != CompressionType.none) {
      warnings.add('mimetype 被压缩（${compression?.name ?? 'unknown'}），不符合 OCF');
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

/// 归档后端：惰性索引或旧的整本解码。
abstract class _ArchiveBackend {
  int get length;
  bool contains(String path);
  int? uncompressedSizeOf(String path);
  Uint8List? readBytes(String path);
  _PreparedEntry? prepareEntry(String path);
  Future<_PreparedEntry?> prepareEntryAsync(String path);
  bool commitEntry(String path, Object identity, String? error);
  Uint8List? readHead(String path, int maxBytes);
  CompressionType? compressionOf(String path);
  void close();
}

class _OverlayArchiveBackend implements _ArchiveBackend {
  _OverlayArchiveBackend(this.base, this.changes);
  final EpubArchive base;
  final Map<String, Uint8List?> changes;
  bool closed = false;

  @override
  int get length => closed
      ? 0
      : {...base.names.where(contains), ...changes.keys.where(contains)}.length;
  @override
  bool contains(String path) =>
      !closed &&
      (changes.containsKey(path) ? changes[path] != null : base.contains(path));
  @override
  int? uncompressedSizeOf(String path) => closed
      ? null
      : changes.containsKey(path)
      ? changes[path]?.length
      : base.uncompressedSizeOf(path);
  @override
  Uint8List? readBytes(String path) {
    if (closed) return null;
    if (!changes.containsKey(path)) return base.readBytes(path);
    final bytes = changes[path];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  _PreparedEntry? prepareEntry(String path) {
    if (closed) return null;
    if (!changes.containsKey(path)) return base._backend.prepareEntry(path);
    final bytes = changes[path];
    return bytes == null
        ? null
        : (
            identity: bytes,
            payload: EpubEntryPayload.decoded(Uint8List.fromList(bytes)),
          );
  }

  @override
  Future<_PreparedEntry?> prepareEntryAsync(String path) async => closed
      ? null
      : changes.containsKey(path)
      ? prepareEntry(path)
      : base._backend.prepareEntryAsync(path);
  @override
  bool commitEntry(String path, Object identity, String? error) =>
      !closed &&
      (changes.containsKey(path)
          ? error == null && identical(changes[path], identity)
          : base._backend.commitEntry(path, identity, error));
  @override
  Uint8List? readHead(String path, int maxBytes) {
    if (closed) return null;
    if (!changes.containsKey(path)) return base.readHead(path, maxBytes);
    final bytes = changes[path];
    return bytes == null
        ? null
        : Uint8List.fromList(bytes.take(maxBytes < 0 ? 0 : maxBytes).toList());
  }

  @override
  CompressionType? compressionOf(String path) => !contains(path)
      ? null
      : changes.containsKey(path)
      ? CompressionType.none
      : base.compressionOf(path);
  @override
  void close() {
    if (closed) return;
    closed = true;
    changes.clear();
    base.close();
  }
}

class _ZipIndexBackend implements _ArchiveBackend {
  _ZipIndexBackend(this._index);

  final ZipIndex _index;

  @override
  int get length => _index.entries.length;

  @override
  bool contains(String path) => _index.contains(path);

  @override
  int? uncompressedSizeOf(String path) =>
      _index.entries[path]?.uncompressedSize;

  @override
  Uint8List? readBytes(String path) => _index.readBytes(path);

  @override
  _PreparedEntry? prepareEntry(String path) {
    final prepared = _index.prepareEntry(path);
    return prepared == null
        ? null
        : (identity: prepared.entry, payload: prepared.payload);
  }

  @override
  Future<_PreparedEntry?> prepareEntryAsync(String path) async {
    final prepared = await _index.prepareEntryAsync(path);
    return prepared == null
        ? null
        : (identity: prepared.entry, payload: prepared.payload);
  }

  @override
  bool commitEntry(String path, Object identity, String? error) =>
      identity is ZipEntryInfo &&
      identity.name == path &&
      _index.commitEntry(identity, error);

  @override
  Uint8List? readHead(String path, int maxBytes) =>
      _index.readHead(path, maxBytes);

  @override
  CompressionType? compressionOf(String path) {
    return switch (_index.methodOf(path)) {
      0 => CompressionType.none,
      8 => CompressionType.deflate,
      12 => CompressionType.bzip2,
      93 => CompressionType.zstd,
      _ => null,
    };
  }

  @override
  void close() {
    _index.release();
  }
}

class _DecodedArchiveBackend implements _ArchiveBackend {
  _DecodedArchiveBackend(this._entries);

  final Map<String, ArchiveFile> _entries;

  @override
  int get length => _entries.length;

  @override
  bool contains(String path) => _entries.containsKey(path);

  @override
  int? uncompressedSizeOf(String path) => _entries[path]?.size;

  @override
  Uint8List? readBytes(String path) {
    final entry = _entries[path];
    return entry == null ? null : Uint8List.fromList(entry.content);
  }

  @override
  _PreparedEntry? prepareEntry(String path) {
    final entry = _entries[path];
    if (entry == null) return null;
    // 不推断 ArchiveFile.rawContent 的编码，沿用特殊压缩与加密兼容路径。
    return (
      identity: entry,
      payload: EpubEntryPayload.decoded(Uint8List.fromList(entry.content)),
    );
  }

  @override
  Future<_PreparedEntry?> prepareEntryAsync(String path) async =>
      prepareEntry(path);

  @override
  bool commitEntry(String path, Object identity, String? error) =>
      error == null && identical(_entries[path], identity);

  @override
  Uint8List? readHead(String path, int maxBytes) {
    final bytes = readBytes(path);
    if (bytes == null || maxBytes <= 0) {
      return bytes == null ? null : Uint8List(0);
    }
    return bytes.length <= maxBytes
        ? bytes
        : Uint8List.sublistView(bytes, 0, maxBytes);
  }

  @override
  CompressionType? compressionOf(String path) => _entries[path]?.compression;

  @override
  void close() {
    for (final entry in _entries.values) {
      entry.clear();
    }
    _entries.clear();
  }
}
