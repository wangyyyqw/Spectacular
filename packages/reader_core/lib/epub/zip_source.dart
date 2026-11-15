import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'epub_entry.dart';
import 'epub_exception.dart';
import 'epub_limits.dart';

export 'epub_entry.dart' show ZipEntryInfo;

/// ZIP 字节来源：内存或磁盘文件。
///
/// 文件后端每次只读取需要的区间，内存占用只与中央目录和单个条目有关。
abstract class ZipByteSource {
  /// 归档总字节数。
  int get length;

  /// 读取 `[offset, offset + count)`；越界时截断到归档末尾。
  Uint8List readRange(int offset, int count);

  /// `readRange` 是否已经返回独立副本。
  ///
  /// 文件后端每次 `readSync` 都是新数组；内存后端返回归档字节的视图，
  /// 公开读取结果前仍需复制，避免调用方修改归档内容。
  bool get rangesAreIndependent => false;

  /// 释放底层句柄。
  Future<void> close();

  /// 同步释放底层句柄；阅读页销毁与导入 isolate 结束时使用。
  void closeSync();

  /// 从字节打开（不复制调用方数据）。
  static ZipByteSource fromBytes(Uint8List bytes) => _MemoryZipSource(bytes);

  /// 从文件打开。
  static Future<ZipByteSource> fromFile(File file) async {
    final handle = await file.open();
    return _FileZipSource(file, handle, await handle.length());
  }
}

class _MemoryZipSource implements ZipByteSource {
  _MemoryZipSource(this._bytes);

  Uint8List? _bytes;

  @override
  int get length => _bytes?.length ?? 0;

  @override
  bool get rangesAreIndependent => false;

  @override
  Uint8List readRange(int offset, int count) {
    final bytes = _bytes;
    if (bytes == null || offset < 0 || offset >= bytes.length) {
      return Uint8List(0);
    }
    final end = (offset + count).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  Future<void> close() async {
    _bytes = null;
  }

  @override
  void closeSync() {
    _bytes = null;
  }
}

class _FileZipSource implements ZipByteSource {
  _FileZipSource(this._file, this._handle, this._length);

  final File _file;
  final RandomAccessFile _handle;
  final int _length;
  bool _closed = false;

  @override
  int get length => _length;

  @override
  bool get rangesAreIndependent => true;

  @override
  Uint8List readRange(int offset, int count) {
    if (offset < 0 || offset >= _length || count <= 0) {
      return Uint8List(0);
    }
    final end = (offset + count).clamp(0, _length);
    _handle.setPositionSync(offset);
    return _handle.readSync(end - offset);
  }

  /// 独立句柄异步读取，不与同步头部探测共享游标或在途 IO。
  Future<Uint8List> readRangeAsync(int offset, int count) async {
    if (_closed || offset < 0 || offset >= _length || count <= 0) {
      return Uint8List(0);
    }
    final handle = await _file.open();
    try {
      if (_closed) return Uint8List(0);
      await handle.setPosition(offset);
      final bytes = await handle.read(
        (offset + count).clamp(0, _length) - offset,
      );
      return _closed ? Uint8List(0) : bytes;
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _handle.close();
  }

  @override
  void closeSync() {
    if (_closed) return;
    _closed = true;
    _handle.closeSync();
  }
}

/// 惰性 ZIP 索引：解析中央目录，按需解压单个条目。
///
/// 不支持的变体（ZIP64、加密、bzip2/zstd）返回 null，由调用方回退到
/// `package:archive`，保证既有兼容行为不倒退。
class ZipIndex {
  ZipIndex._(
    this._source,
    this.entries,
    this.order,
    this._verifyCrc,
    this._limits,
  );

  final ZipByteSource _source;

  /// 读取时是否比对 CRC。阅读路径关闭（导入时已校验过一次），避免大图片
  /// 每次布局探测都重复算 CRC。
  final bool _verifyCrc;
  final EpubArchiveLimits _limits;

  /// 全部文件条目（不含目录）。
  final Map<String, ZipEntryInfo> entries;

  /// ZIP 顺序（去重后）。
  final List<String> order;

  /// 打开期诊断（损坏条目、局部头修补）。
  final List<String> diagnostics = <String>[];

  /// 已修补的局部头偏移（避免同一坏条目反复扫描）。
  final Map<String, int> _repairedOffsets = <String, int>{};

  /// 解析中央目录；不支持的归档返回 null。
  ///
  /// [validateHeaders] 为 true 时逐条校验局部头签名与文件名（不读内容），
  /// 用于保持既有「局部头错位」诊断语义；文件后端按需校验以缩短打开时间。
  static ZipIndex? tryParse(
    ZipByteSource source, {
    bool validateHeaders = true,
    bool verifyCrc = false,
    EpubArchiveLimits limits = const EpubArchiveLimits(),
  }) {
    final eocd = _findEocd(source);
    if (eocd == null) {
      return null;
    }
    final tail = source.readRange(eocd, 22);
    if (tail.length < 22) {
      return null;
    }
    final data = ByteData.sublistView(tail);
    final count = data.getUint16(10, Endian.little);
    final directorySize = data.getUint32(12, Endian.little);
    final directoryOffset = data.getUint32(16, Endian.little);
    // ZIP64 / 分卷：交给 package:archive 处理。
    if (count == 0xFFFF ||
        directorySize == 0xFFFFFFFF ||
        directoryOffset == 0xFFFFFFFF) {
      return null;
    }
    if (directoryOffset + directorySize > source.length) {
      return null;
    }
    if (directorySize > limits.maxEntryBytes) {
      throw const EpubException('E_ARCHIVE', 'ZIP 中央目录超出安全预算');
    }
    final directory = source.readRange(directoryOffset, directorySize);
    if (directory.length < directorySize) {
      return null;
    }
    final directoryData = ByteData.sublistView(directory);
    final entries = <String, ZipEntryInfo>{};
    final order = <String>[];
    var cursor = 0;
    for (var i = 0; i < count; i++) {
      if (cursor + 46 > directory.length ||
          directoryData.getUint32(cursor, Endian.little) != 0x02014b50) {
        return null;
      }
      final flags = directoryData.getUint16(cursor + 8, Endian.little);
      final method = directoryData.getUint16(cursor + 10, Endian.little);
      final crc = directoryData.getUint32(cursor + 16, Endian.little);
      final compressedSize = directoryData.getUint32(
        cursor + 20,
        Endian.little,
      );
      final uncompressedSize = directoryData.getUint32(
        cursor + 24,
        Endian.little,
      );
      final nameLength = directoryData.getUint16(cursor + 28, Endian.little);
      final extraLength = directoryData.getUint16(cursor + 30, Endian.little);
      final commentLength = directoryData.getUint16(cursor + 32, Endian.little);
      final localOffset = directoryData.getUint32(cursor + 42, Endian.little);
      if (flags & 0x1 != 0 ||
          method == 99 ||
          (method != 0 && method != 8) ||
          compressedSize == 0xFFFFFFFF ||
          uncompressedSize == 0xFFFFFFFF ||
          localOffset == 0xFFFFFFFF) {
        return null;
      }
      final nameEnd = cursor + 46 + nameLength;
      if (nameEnd > directory.length) {
        return null;
      }
      final rawNameBytes = Uint8List.sublistView(
        directory,
        cursor + 46,
        nameEnd,
      );
      final name = _decodeName(rawNameBytes, flags);
      cursor = nameEnd + extraLength + commentLength;
      if (name.endsWith('/') || name.endsWith('\\') || name.isEmpty) {
        continue;
      }
      // 与 package:archive 一致：重名条目保留第一个。
      if (entries.containsKey(name)) {
        continue;
      }
      entries[name] = ZipEntryInfo(
        name: name,
        rawNameBytes: Uint8List.fromList(rawNameBytes),
        method: method,
        crc32: crc,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localOffset,
        flags: flags,
      );
      order.add(name);
    }
    final budget = EpubDecodeBudget(limits);
    for (final name in List<String>.of(order)) {
      final entry = entries[name]!;
      if (!budget.admit(name, entry.compressedSize, entry.uncompressedSize)) {
        entries.remove(name);
        order.remove(name);
      }
    }
    final index = ZipIndex._(source, entries, order, verifyCrc, limits);
    index.diagnostics.addAll(budget.diagnostics);
    if (validateHeaders) {
      for (final name in List<String>.of(order)) {
        if (!index._validateLocalHeader(entries[name]!)) {
          entries.remove(name);
          order.remove(name);
        }
      }
    }
    return index;
  }

  /// 是否存在指定路径。
  bool contains(String path) => entries.containsKey(path);

  /// 读取条目字节；缺失或损坏返回 null。
  Uint8List? readBytes(String path) {
    final entry = entries[path];
    if (entry == null) return null;
    try {
      final range = _fullReadRange(entry);
      if (range == null) return null;
      final result = decodeEpubEntryChunks(
        entry,
        _verifyCrc,
        () => _independentRange(range.start, range.length),
        () => _entryChunks(entry, range.start),
        limits: _limits,
      );
      commitEntry(entry, result.error);
      return result.bytes;
    } catch (error) {
      _drop(entry, 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压失败（$error）');
      return null;
    }
  }

  /// 只为当前完整读取物化压缩条目；句柄与修复状态仍由本索引持有。
  ({ZipEntryInfo entry, EpubEntryPayload payload})? prepareEntry(String path) {
    final entry = entries[path];
    if (entry == null) return null;
    try {
      final range = _fullReadRange(entry);
      if (range == null) return null;
      final bytes = _independentRange(range.start, range.length);
      if (bytes.length != range.length) {
        final message = 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整';
        if (entry.method != 0) throw _ZipEntryFailure(message);
        _drop(entry, message);
        return null;
      }
      return (
        entry: entry,
        payload: EpubEntryPayload.compressed(
          bytes,
          entry,
          verifyCrc: _verifyCrc,
          limits: _limits,
        ),
      );
    } catch (error) {
      _drop(entry, 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压失败（$error）');
      return null;
    }
  }

  /// 大块压缩数据异步读盘；局部头校验与条目凭据仍由当前索引持有。
  Future<({ZipEntryInfo entry, EpubEntryPayload payload})?> prepareEntryAsync(
    String path,
  ) async {
    final source = _source;
    if (source is! _FileZipSource) return prepareEntry(path);
    final entry = entries[path];
    if (entry == null) return null;
    try {
      final range = _fullReadRange(entry);
      if (range == null) return null;
      final bytes = await source.readRangeAsync(range.start, range.length);
      if (!identical(entries[path], entry)) return null;
      if (bytes.length != range.length) {
        throw _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整');
      }
      return (
        entry: entry,
        payload: EpubEntryPayload.compressed(
          bytes,
          entry,
          verifyCrc: _verifyCrc,
          limits: _limits,
        ),
      );
    } catch (error) {
      if (identical(entries[path], entry)) {
        _drop(entry, 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压失败（$error）');
      }
      return null;
    }
  }

  /// 仅当前条目可接收解码结果；关闭或旧条目晚到不会修改索引。
  bool commitEntry(ZipEntryInfo entry, String? error) {
    if (!identical(entries[entry.name], entry)) return false;
    if (error != null) _drop(entry, error);
    return true;
  }

  Uint8List _independentRange(int start, int count) {
    final bytes = _source.readRange(start, count);
    return _source.rangesAreIndependent ? bytes : Uint8List.fromList(bytes);
  }

  ({int start, int length})? _fullReadRange(ZipEntryInfo entry) {
    final offset = _headerOffsetFor(entry);
    if (offset == null) {
      _drop(entry, 'E_ZIP_LOCAL_HEADER: 条目 ${entry.name} 的局部头无法定位');
      return null;
    }
    final header = _source.readRange(offset, 30);
    if (header.length < 30) {
      _drop(entry, 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 的局部头被截断');
      return null;
    }
    final data = ByteData.sublistView(header);
    final start =
        offset +
        30 +
        data.getUint16(26, Endian.little) +
        data.getUint16(28, Endian.little);
    if (start + entry.compressedSize > _source.length) {
      _drop(entry, 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整');
      return null;
    }
    return (start: start, length: entry.compressedSize);
  }

  Iterable<Uint8List> _entryChunks(ZipEntryInfo entry, int start) sync* {
    var cursor = start;
    var remaining = entry.compressedSize;
    while (remaining > 0) {
      final count = remaining > _ioChunkSize ? _ioChunkSize : remaining;
      final chunk = _source.readRange(cursor, count);
      if (chunk.length != count) {
        throw _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整');
      }
      yield chunk;
      cursor += count;
      remaining -= count;
    }
  }

  /// 只读取条目开头至多 [maxBytes] 个解压字节。
  ///
  /// 图片尺寸、媒体类型嗅探只需要文件头。对 deflate 条目按压缩块增量解压，
  /// 达到上限立即停止，避免为了几十字节的 PNG/JPEG 头解压整张图片。
  Uint8List? readHead(String path, int maxBytes) {
    final entry = entries[path];
    if (entry == null) {
      return null;
    }
    if (maxBytes <= 0) {
      return Uint8List(0);
    }
    try {
      final range = _compressedRange(entry);
      final limit = entry.uncompressedSize < maxBytes
          ? entry.uncompressedSize
          : maxBytes;
      if (limit <= 0) {
        return Uint8List(0);
      }
      if (entry.method == 0) {
        final count = range.length < limit ? range.length : limit;
        final bytes = _source.readRange(range.start, count);
        if (bytes.length != count) {
          return null;
        }
        return _source.rangesAreIndependent ? bytes : Uint8List.fromList(bytes);
      }
      final output = Uint8List(limit);
      final sink = _OutputSink(output, truncate: true);
      final decoder = ZLibDecoder(raw: true).startChunkedConversion(sink);
      var cursor = range.start;
      var remaining = range.length;
      while (remaining > 0 && !sink.full) {
        final count = remaining > _ioChunkSize ? _ioChunkSize : remaining;
        final chunk = _source.readRange(cursor, count);
        if (chunk.length != count) {
          break;
        }
        try {
          decoder.add(chunk);
        } catch (_) {
          break;
        }
        cursor += count;
        remaining -= count;
      }
      try {
        decoder.close();
      } catch (_) {
        // 头部已足够时，不因尾部损坏丢弃当前章节资源。
      }
      return sink.written == output.length
          ? output
          : Uint8List.sublistView(output, 0, sink.written);
    } catch (_) {
      return null;
    }
  }

  /// 校验单个条目（打开期 CRC 扫描用）；损坏时移除并记诊断。
  ///
  /// 小条目直接解压校验；大条目走分块解压 + 增量 CRC，既保持「导入时
  /// 完整校验」的既有语义，也不把整张图片或整段字体读入内存。
  bool verifyEntry(ZipEntryInfo entry) {
    if (entry.uncompressedSize <= _inlineVerifyLimit) {
      return readBytes(entry.name) != null;
    }
    final sink = _Crc32Sink(
      maxBytes: entry.uncompressedSize > 0 ? entry.uncompressedSize : null,
    );
    try {
      final range = _compressedRange(entry);
      final input = entry.method == 0
          ? null
          : ZLibDecoder(raw: true).startChunkedConversion(sink);
      var offset = range.start;
      var remaining = range.length;
      while (remaining > 0) {
        final count = remaining > _ioChunkSize ? _ioChunkSize : remaining;
        final chunk = _source.readRange(offset, count);
        if (chunk.length != count) {
          throw _ZipEntryFailure(
            'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整',
          );
        }
        if (input == null) {
          sink.add(chunk);
        } else {
          input.add(chunk);
        }
        offset += chunk.length;
        remaining -= chunk.length;
      }
      input?.close();
      if (sink.length != entry.uncompressedSize) {
        throw _ZipEntryFailure(
          'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压尺寸与声明不符',
        );
      }
      if (sink.value != entry.crc32) {
        throw _ZipEntryFailure(
          'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 损坏（CRC 不符）',
        );
      }
      return true;
    } on _ZipEntryFailure catch (failure) {
      _drop(entry, failure.diagnostic);
      return false;
    } catch (error) {
      _drop(entry, 'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压失败（$error）');
      return false;
    }
  }

  /// 条目压缩方式（0 / 8）。
  int? methodOf(String path) => entries[path]?.method;

  /// 释放底层字节来源（内存引用或文件句柄）并清空条目表。
  void release() {
    entries.clear();
    order.clear();
    _source.closeSync();
  }

  void _drop(ZipEntryInfo entry, String diagnostic) {
    entries.remove(entry.name);
    order.remove(entry.name);
    if (!diagnostics.contains(diagnostic)) {
      diagnostics.add(diagnostic);
    }
  }

  /// 大条目校验用：定位压缩数据区间，不读取内容。
  ({int start, int length}) _compressedRange(ZipEntryInfo entry) {
    final offset = _headerOffsetFor(entry);
    if (offset == null) {
      throw _ZipEntryFailure('E_ZIP_LOCAL_HEADER: 条目 ${entry.name} 的局部头无法定位');
    }
    final header = _source.readRange(offset, 30);
    if (header.length < 30) {
      throw _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 的局部头被截断');
    }
    final headerData = ByteData.sublistView(header);
    final nameLength = headerData.getUint16(26, Endian.little);
    final extraLength = headerData.getUint16(28, Endian.little);
    final start = offset + 30 + nameLength + extraLength;
    if (start + entry.compressedSize > _source.length) {
      throw _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整');
    }
    return (start: start, length: entry.compressedSize);
  }

  /// 读取并校验局部头；失败时扫描修补，仍失败则移除条目。
  bool _validateLocalHeader(ZipEntryInfo entry) {
    if (_headerOffsetFor(entry) != null) {
      return true;
    }
    _drop(entry, 'E_ZIP_LOCAL_HEADER: 条目 ${entry.name} 的局部头无法定位');
    return false;
  }

  int? _headerOffsetFor(ZipEntryInfo entry) {
    final repaired = _repairedOffsets[entry.name];
    if (repaired != null) {
      return repaired;
    }
    final nameBytes = entry.rawNameBytes;
    if (_matchesHeader(entry.localHeaderOffset, nameBytes)) {
      return entry.localHeaderOffset;
    }
    final located = _locateHeader(entry.localHeaderOffset, nameBytes);
    if (located != null) {
      _repairedOffsets[entry.name] = located;
      final diagnostic = 'E_ZIP_LOCAL_HEADER: 条目 ${entry.name} 局部头偏移错位，已扫描修补';
      if (!diagnostics.contains(diagnostic)) {
        diagnostics.add(diagnostic);
      }
      return located;
    }
    return null;
  }

  bool _matchesHeader(int offset, Uint8List nameBytes) {
    if (offset < 0 || offset + 30 > _source.length) {
      return false;
    }
    final header = _source.readRange(offset, 30);
    if (header.length < 30 ||
        ByteData.sublistView(header).getUint32(0, Endian.little) !=
            0x04034b50) {
      return false;
    }
    final nameLength = ByteData.sublistView(header)
        .getUint16(26, Endian.little);
    if (nameLength != nameBytes.length) {
      return false;
    }
    final actual = _source.readRange(offset + 30, nameLength);
    if (actual.length != nameLength) {
      return false;
    }
    for (var i = 0; i < nameLength; i++) {
      if (actual[i] != nameBytes[i]) {
        return false;
      }
    }
    return true;
  }

  int? _locateHeader(int expected, Uint8List nameBytes) {
    final start = expected - 4096 < 0 ? 0 : expected - 4096;
    final end = expected + 65536 > _source.length
        ? _source.length
        : expected + 65536;
    for (var offset = start; offset + 30 <= end; offset++) {
      if (_matchesHeader(offset, nameBytes)) {
        return offset;
      }
    }
    return null;
  }

  static String _decodeName(Uint8List bytes, int flags) {
    if (flags & 0x800 != 0) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static int? _findEocd(ZipByteSource source) {
    if (source.length < 22) {
      return null;
    }
    final tailLength = source.length > 66000 ? 66000 : source.length;
    final tailStart = source.length - tailLength;
    final tail = source.readRange(tailStart, tailLength);
    final data = ByteData.sublistView(tail);
    for (var i = tail.length - 22; i >= 0; i--) {
      if (data.getUint32(i, Endian.little) != 0x06054b50) {
        continue;
      }
      final commentLength = data.getUint16(i + 20, Endian.little);
      if (i + 22 + commentLength == tail.length) {
        return tailStart + i;
      }
    }
    return null;
  }
}

final Uint32List _crcTable = _buildCrcTable();

const int _inlineVerifyLimit = 1024 * 1024;
const int _ioChunkSize = 64 * 1024;

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var value = i;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? (value >> 1) ^ 0xEDB88320 : value >> 1;
    }
    table[i] = value;
  }
  return table;
}

int _crc32Update(int crc, List<int> bytes) {
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc;
}

class _OutputSink implements Sink<List<int>> {
  _OutputSink(this._output, {this.truncate = false});

  final Uint8List _output;
  final bool truncate;
  int written = 0;

  bool get full => written >= _output.length;

  @override
  void add(List<int> data) {
    if (data.isEmpty) {
      return;
    }
    final available = _output.length - written;
    if (available <= 0) {
      if (truncate) {
        return;
      }
      throw const _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 解压尺寸超出声明值');
    }
    final count = data.length < available ? data.length : available;
    _output.setRange(written, written + count, data);
    written += count;
    if (!truncate && count < data.length) {
      throw const _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 解压尺寸超出声明值');
    }
  }

  @override
  void close() {}
}

class _Crc32Sink implements Sink<List<int>> {
  _Crc32Sink({this.maxBytes});

  final int? maxBytes;
  var _crc = 0xFFFFFFFF;
  var length = 0;

  int get value => _crc ^ 0xFFFFFFFF;

  @override
  void add(List<int> data) {
    length += data.length;
    final limit = maxBytes;
    if (limit != null && length > limit) {
      throw _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 解压尺寸超出声明值');
    }
    _crc = _crc32Update(_crc, data);
  }

  @override
  void close() {}
}

class _ZipEntryFailure implements Exception {
  const _ZipEntryFailure(this.diagnostic);

  final String diagnostic;
}
