import 'epub_exception.dart';

/// ZIP 读取、纯数据解码和旧归档兜底共用的解压预算。
class EpubArchiveLimits {
  const EpubArchiveLimits({
    this.maxEntryBytes = 64 * 1024 * 1024,
    this.maxArchiveBytes = 512 * 1024 * 1024,
  }) : assert(maxEntryBytes > 0),
       assert(maxArchiveBytes > 0);

  /// 单条目压缩输入和解压输出各自允许的最大尺寸。
  final int maxEntryBytes;

  /// 各条目压缩输入与解压声明较大值的总量；整本兜底输入也受此限制。
  final int maxArchiveBytes;

  String? entryFailure(String name, int compressedSize, int uncompressedSize) {
    if (compressedSize < 0 ||
        uncompressedSize < 0 ||
        compressedSize > maxEntryBytes ||
        uncompressedSize > maxEntryBytes) {
      return 'E_ZIP_RESOURCE_LIMIT: 条目 $name 超出单条目预算 '
          '（压缩 $compressedSize，解压 $uncompressedSize，上限 $maxEntryBytes 字节）';
    }
    return null;
  }
}

/// 按目录条目累计预算；重复读取同一条目不会重复计入整本大小。
class EpubDecodeBudget {
  EpubDecodeBudget(this.limits);
  final EpubArchiveLimits limits;
  final List<String> diagnostics = [];
  int _total = 0;

  bool admit(String name, int compressedSize, int uncompressedSize) {
    final failure = limits.entryFailure(name, compressedSize, uncompressedSize);
    if (failure != null) {
      diagnostics.add(failure);
      return false;
    }
    final entryBytes = compressedSize > uncompressedSize
        ? compressedSize
        : uncompressedSize;
    if (entryBytes > limits.maxArchiveBytes - _total) {
      throw EpubException(
        'E_ARCHIVE',
        '归档解压总量超出安全预算',
        detail: {
          'limitBytes': limits.maxArchiveBytes,
          'entryBytes': entryBytes,
          'admittedBytes': _total,
        },
      );
    }
    _total += entryBytes;
    if (uncompressedSize >= 1024 * 1024 &&
        (compressedSize == 0 || uncompressedSize > compressedSize * 100)) {
      diagnostics.add(
        'W_ZIP_COMPRESSION_RATIO: 条目 $name 压缩比异常 '
        '（压缩 $compressedSize，解压 $uncompressedSize 字节，仍在尺寸预算内）',
      );
    }
    return true;
  }
}
