/// 页索引持久化（P7-22；对照 Reeden pagination 层 RPI2——5 字段最小集：
/// magic + schemaVersion + 页起点数组 + 每页偏移信息，650 号 §0/§3）。
///
/// 索引记录的是**分页决策结果**（每页从哪个块的哪一行开始），不携带
/// 行布局本身——重开书时块经测量缓存重建后按边界直接切片，跳过分页
/// 状态机；完整的零重排冷启动需要 document/styles 层配合（P7-23）。
///
/// 容错：魔数不对 / schema 版本不匹配 / 字节截断 / 校验和不对 一律
/// 返回 null，由调用方静默重建（结果与重排一致）。
library;

import 'dart:typed_data';

import 'paginator.dart';

/// 单页起点记录。
class PageIndexEntry {
  /// 创建记录。
  const PageIndexEntry({
    required this.blockIndex,
    required this.startLine,
    required this.usedHeight,
    required this.pageHeight,
    required this.topPadding,
  });

  /// 页首块的序号（本章块列表下标）。
  final int blockIndex;

  /// 页首块内的起始行（0 = 整块开始）。
  final int startLine;

  /// 该页已用高度（几何校验用）。
  final double usedHeight;

  /// 该页页高。
  final double pageHeight;

  /// 该页顶部留白（首页才有）。
  final double topPadding;

  @override
  bool operator ==(Object other) =>
      other is PageIndexEntry &&
      other.blockIndex == blockIndex &&
      other.startLine == startLine &&
      other.usedHeight == usedHeight &&
      other.pageHeight == pageHeight &&
      other.topPadding == topPadding;

  @override
  int get hashCode => Object.hash(
    blockIndex,
    startLine,
    usedHeight,
    pageHeight,
    topPadding,
  );
}

/// 一章的页索引。
class PageIndex {
  /// 创建索引。
  const PageIndex({required this.schemaVersion, required this.entries});

  /// 当前 schema 版本；换代即整体失效（不迁移，对照 RPI2 换代策略）。
  static const int currentSchemaVersion = 1;

  /// schema 版本。
  final int schemaVersion;

  /// 页起点数组（页序敏感）。
  final List<PageIndexEntry> entries;

  /// 魔数「RPI1」（u32 big-endian，对照 RPI2 命名传统）。
  static const int _magic = 0x52504931;

  static const int _headerBytes = 4 + 2 + 4;
  static const int _entryBytes = 4 + 4 + 8 + 8 + 8;

  /// 从分页结果提取索引；[blocks] 为本章块列表（块序号基准）。
  static PageIndex from(
    ChapterPagination pagination,
    List<PageBlock> blocks,
  ) {
    final indexOf = <PageBlock, int>{
      for (var i = 0; i < blocks.length; i++) blocks[i]: i,
    };
    return PageIndex(
      schemaVersion: currentSchemaVersion,
      entries: <PageIndexEntry>[
        for (final page in pagination.pages)
          PageIndexEntry(
            blockIndex:
                page.slices.isEmpty
                    ? 0
                    : indexOf[page.slices.first.block] ?? 0,
            startLine: page.slices.isEmpty ? 0 : page.slices.first.startLine,
            usedHeight: page.usedHeight,
            pageHeight: page.pageHeight,
            topPadding: page.topPadding,
          ),
      ],
    );
  }

  /// 序列化；魔数 + schema + 条目 + 累加和。
  Uint8List encode() {
    final bytes = ByteData(_headerBytes + entries.length * _entryBytes + 4);
    var offset = 0;
    bytes.setUint32(offset, _magic, Endian.big);
    offset += 4;
    bytes.setUint16(offset, schemaVersion, Endian.big);
    offset += 2;
    bytes.setUint32(offset, entries.length, Endian.big);
    offset += 4;
    var checksum = 0;
    for (final entry in entries) {
      bytes.setUint32(offset, entry.blockIndex, Endian.big);
      bytes.setUint32(offset + 4, entry.startLine, Endian.big);
      bytes.setFloat64(offset + 8, entry.usedHeight, Endian.big);
      bytes.setFloat64(offset + 16, entry.pageHeight, Endian.big);
      bytes.setFloat64(offset + 24, entry.topPadding, Endian.big);
      for (var i = 0; i < _entryBytes; i++) {
        checksum = (checksum + bytes.getUint8(offset + i)) & 0xFFFFFFFF;
      }
      offset += _entryBytes;
    }
    bytes.setUint32(offset, checksum, Endian.big);
    return bytes.buffer.asUint8List();
  }

  /// 反序列化；任何结构问题返回 null（调用方静默重建）。
  static PageIndex? decode(Uint8List bytes) {
    if (bytes.length < _headerBytes + 4) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.big) != _magic) {
      return null;
    }
    final schemaVersion = data.getUint16(4, Endian.big);
    if (schemaVersion != currentSchemaVersion) {
      return null;
    }
    final count = data.getUint32(6, Endian.big);
    if (bytes.length != _headerBytes + count * _entryBytes + 4) {
      return null;
    }
    var checksum = 0;
    for (var i = _headerBytes; i < _headerBytes + count * _entryBytes; i++) {
      checksum = (checksum + bytes[i]) & 0xFFFFFFFF;
    }
    if (data.getUint32(bytes.length - 4, Endian.big) != checksum) {
      return null;
    }
    final entries = <PageIndexEntry>[];
    var offset = _headerBytes;
    for (var i = 0; i < count; i++) {
      entries.add(
        PageIndexEntry(
          blockIndex: data.getUint32(offset, Endian.big),
          startLine: data.getUint32(offset + 4, Endian.big),
          usedHeight: data.getFloat64(offset + 8, Endian.big),
          pageHeight: data.getFloat64(offset + 16, Endian.big),
          topPadding: data.getFloat64(offset + 24, Endian.big),
        ),
      );
      offset += _entryBytes;
    }
    return PageIndex(schemaVersion: schemaVersion, entries: entries);
  }

  /// 按索引边界重放：把 [blocks] 的行切成页（跳过分页状态机）。
  ///
  /// 边界非法（块序号越界 / 行号越界 / 空索引）返回 null，调用方回退
  /// 正常分页；重放结果与重排一致（边界即决策记录）。
  static List<PageContent>? apply(
    PageIndex index,
    List<PageBlock> blocks, {
    required int spineIndex,
  }) {
    if (index.entries.isEmpty) {
      return null;
    }
    final pages = <PageContent>[];
    for (var i = 0; i < index.entries.length; i++) {
      final entry = index.entries[i];
      if (entry.blockIndex < 0 || entry.blockIndex >= blocks.length) {
        return null;
      }
      final startBlock = blocks[entry.blockIndex];
      if (entry.startLine < 0 ||
          entry.startLine > startBlock.layout.lineCount) {
        return null;
      }
      // 本页终点 = 下一页起点（不含）；末页取最后一块的块尾。
      // 下一页起点恰好是某块的首行（startLine=0）时，本页终点是
      // 前一块的块尾（页在块边界结束）。
      final next = i + 1 < index.entries.length ? index.entries[i + 1] : null;
      var endBlockIndex = next?.blockIndex ?? blocks.length - 1;
      if (endBlockIndex < entry.blockIndex || endBlockIndex >= blocks.length) {
        return null;
      }
      var endLine = next == null
          ? blocks[endBlockIndex].layout.lineCount
          : next.startLine;
      if (next != null && endLine == 0) {
        endBlockIndex -= 1;
        if (endBlockIndex < entry.blockIndex) {
          return null; // 空页边界（重排不会产出）。
        }
        endLine = blocks[endBlockIndex].layout.lineCount;
      }
      if (endLine < 0 || endLine > blocks[endBlockIndex].layout.lineCount) {
        return null;
      }
      if (endBlockIndex == entry.blockIndex && endLine <= entry.startLine) {
        return null; // 空页边界（重排不会产出）。
      }
      final slices = <PageBlockSlice>[];
      var used = 0.0;
      var bi = entry.blockIndex;
      var line = entry.startLine;
      while (true) {
        final block = blocks[bi];
        final stop = bi == endBlockIndex ? endLine : block.layout.lineCount;
        if (stop < line || stop > block.layout.lineCount) {
          return null;
        }
        if (stop == line) {
          return null; // 空切片（重排不会产出）。
        }
        final leading = line == 0 ? block.leadingExtent : 0.0;
        final trailing = stop == block.layout.lineCount
            ? block.trailingExtent
            : 0.0;
        var sliceHeight = leading + trailing;
        for (var l = line; l < stop; l++) {
          sliceHeight += block.layout.lines[l].height;
        }
        slices.add(
          PageBlockSlice(
            block: block,
            startLine: line,
            endLine: stop,
            height: sliceHeight,
            leadingExtent: leading,
            trailingExtent: trailing,
            leftInset: block.leftInset,
          ),
        );
        used += sliceHeight;
        if (bi == endBlockIndex) {
          break;
        }
        bi += 1;
        line = 0;
      }
      pages.add(
        PageContent(
          spineIndex: spineIndex,
          pageIndex: pages.length,
          slices: List<PageBlockSlice>.unmodifiable(slices),
          usedHeight: used,
          pageHeight: entry.pageHeight,
          topPadding: entry.topPadding,
        ),
      );
    }
    return pages;
  }
}
