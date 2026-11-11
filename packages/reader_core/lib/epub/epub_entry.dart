import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// ZIP 中央目录中的一个条目。
///
/// 只保存定位信息，不持有压缩或解压后的字节：大型 EPUB（100MB+）打开时
/// 不该把整本内容读进内存。
class ZipEntryInfo {
  /// 创建条目信息。
  const ZipEntryInfo({
    required this.name,
    required this.rawNameBytes,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.flags,
  });

  /// 归档内路径。
  final String name;

  /// 中央目录中的原始文件名字节；局部头必须按原字节比较。
  final Uint8List rawNameBytes;

  /// 压缩方式：0 = store，8 = deflate。
  final int method;

  /// 未压缩内容的 CRC32。
  final int crc32;

  /// 压缩后字节数。
  final int compressedSize;

  /// 未压缩字节数。
  final int uncompressedSize;

  /// 局部头在归档中的偏移。
  final int localHeaderOffset;

  /// 通用标志位。
  final int flags;

  /// 是否使用 UTF-8 文件名。
  bool get usesUtf8Name => flags & 0x800 != 0;
}

/// 可跨 isolate 的完整条目输入；不含归档、文件句柄或读取回调。
///
/// 只用于当前章节和 CSS。完整压缩字节会增加峰值内存，图片前缀与导入
/// 校验继续使用原有流式入口。
class EpubEntryPayload {
  EpubEntryPayload.compressed(
    this.bytes,
    this._entry, {
    required this.verifyCrc,
  });

  /// 恢复读取的归档已在宿主解码，直接交接当前条目的原始字节。
  EpubEntryPayload.decoded(this.bytes) : _entry = null, verifyCrc = false;

  final Uint8List bytes;
  final ZipEntryInfo? _entry;
  final bool verifyCrc;
}

/// 解压失败作为数据返回，由持有归档的宿主移除坏条目并记录诊断。
class EpubEntryDecodeResult {
  const EpubEntryDecodeResult.success(this.bytes) : error = null;
  const EpubEntryDecodeResult.failure(this.error) : bytes = null;

  final Uint8List? bytes;
  final String? error;
}

/// 与同步读取共用解码和 CRC 逻辑，不读取或更改归档状态。
EpubEntryDecodeResult decodeEpubEntry(EpubEntryPayload payload) {
  final entry = payload._entry;
  if (entry == null) return EpubEntryDecodeResult.success(payload.bytes);
  return decodeEpubEntryChunks(
    entry,
    payload.verifyCrc,
    () => payload.bytes,
    () => _payloadChunks(payload.bytes),
  );
}

Iterable<Uint8List> _payloadChunks(Uint8List bytes) sync* {
  for (var start = 0; start < bytes.length; start += _ioChunkSize) {
    final end = (start + _ioChunkSize).clamp(0, bytes.length);
    yield Uint8List.sublistView(bytes, start, end);
  }
}

/// 同步宿主按需提供压缩块；完整 payload 与原有流式读取共用此解码逻辑。
EpubEntryDecodeResult decodeEpubEntryChunks(
  ZipEntryInfo entry,
  bool verifyCrc,
  Uint8List Function() stored,
  Iterable<Uint8List> Function() chunks,
) {
  try {
    final bytes = entry.method == 0 ? stored() : _inflateEntry(entry, chunks());
    if (entry.method == 0 && bytes.length != entry.compressedSize) {
      return EpubEntryDecodeResult.failure(
        'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 数据不完整',
      );
    }
    if (verifyCrc && entry.crc32 != 0 && getCrc32(bytes) != entry.crc32) {
      return EpubEntryDecodeResult.failure(
        'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 损坏（CRC 不符）',
      );
    }
    return EpubEntryDecodeResult.success(bytes);
  } catch (error) {
    return EpubEntryDecodeResult.failure(
      'E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压失败（$error）',
    );
  }
}

Uint8List _inflateEntry(ZipEntryInfo entry, Iterable<Uint8List> chunks) {
  final bytes = Uint8List(entry.uncompressedSize);
  final output = _FullEntrySink(bytes);
  final decoder = ZLibDecoder(raw: true).startChunkedConversion(output);
  for (final chunk in chunks) {
    decoder.add(chunk);
  }
  decoder.close();
  if (output.written != entry.uncompressedSize) {
    throw _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 条目 ${entry.name} 解压尺寸与声明不符');
  }
  return bytes;
}

const int _ioChunkSize = 64 * 1024;

class _FullEntrySink implements Sink<List<int>> {
  _FullEntrySink(this.bytes);
  final Uint8List bytes;
  int written = 0;

  @override
  void add(List<int> data) {
    if (data.isEmpty) return;
    final available = bytes.length - written;
    if (data.length > available) {
      throw const _ZipEntryFailure('E_ZIP_ENTRY_TRUNCATED: 解压尺寸超出声明值');
    }
    bytes.setRange(written, written + data.length, data);
    written += data.length;
  }

  @override
  void close() {}
}

class _ZipEntryFailure implements Exception {
  const _ZipEntryFailure(this.diagnostic);
  final String diagnostic;
}
