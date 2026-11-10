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

import 'dart:collection';
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

  /// 该页相对正文区的顶部偏移（首页才有，可为负值）。
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
  int get hashCode =>
      Object.hash(blockIndex, startLine, usedHeight, pageHeight, topPadding);
}

/// 一章的页索引。
class PageIndex {
  /// 创建索引。
  const PageIndex({required this.schemaVersion, required this.entries});

  /// 当前 schema 版本；换代即整体失效（不迁移，对照 RPI2 换代策略）。
  // 页尾正外边距不再挤走末行，旧版断点与切片高度必须重新计算。
  static const int currentSchemaVersion = 8;

  /// schema 版本。
  final int schemaVersion;

  /// 页起点数组（页序敏感）。
  final List<PageIndexEntry> entries;

  /// 魔数「RPI1」（u32 big-endian，对照 RPI2 命名传统）。
  static const int _magic = 0x52504931;

  static const int _headerBytes = 4 + 2 + 4;
  static const int _entryBytes = 4 + 4 + 8 + 8 + 8;

  /// 从分页结果提取索引；[blocks] 为本章块列表（块序号基准）。
  static PageIndex from(ChapterPagination pagination, List<PageBlock> blocks) {
    final work = _IndexExtraction(pagination, blocks);
    _consumeIndexSteps(work.steps());
    return work.result;
  }

  /// 逐块建立身份映射、逐页提取；取消时不返回部分条目。
  static Future<PageIndex> fromAsync(
    ChapterPagination pagination,
    List<PageBlock> blocks, {
    Future<void> Function()? checkpoint,
  }) async {
    final work = _IndexExtraction(pagination, blocks);
    await _consumeIndexStepsAsync(work.steps(), checkpoint);
    return work.result;
  }

  /// 序列化；魔数 + schema + 条目 + 累加和。
  Uint8List encode() {
    final work = _IndexEncoding(this);
    _consumeIndexSteps(work.steps());
    return work.result;
  }

  /// 格式及校验和沿用同步入口，每条固定长度记录之间检查预算。
  Future<Uint8List> encodeAsync({Future<void> Function()? checkpoint}) async {
    final work = _IndexEncoding(this);
    await _consumeIndexStepsAsync(work.steps(), checkpoint);
    return work.result;
  }

  /// 反序列化；任何结构问题返回 null（调用方静默重建）。
  static PageIndex? decode(Uint8List bytes) {
    final work = _IndexDecoding(bytes);
    _consumeIndexSteps(work.steps());
    return work.result;
  }

  /// 校验和与条目解码都在循环内检查预算；结构错误仍返回 null。
  static Future<PageIndex?> decodeAsync(
    Uint8List bytes, {
    Future<void> Function()? checkpoint,
  }) async {
    final work = _IndexDecoding(bytes);
    await _consumeIndexStepsAsync(work.steps(), checkpoint);
    return work.result;
  }

  /// 按索引边界重放：把 [blocks] 的行切成页（跳过分页状态机）。
  ///
  /// 边界非法（块序号越界 / 行号越界 / 空索引）返回 null，调用方回退
  /// 正常分页；重放结果与重排一致（边界即决策记录）。
  static List<PageContent>? apply(
    PageIndex index,
    List<PageBlock> blocks, {
    required int spineIndex,
    bool trimTextEdges = false,
  }) {
    final work = _IndexReplay(index, blocks, spineIndex, trimTextEdges);
    _consumeIndexSteps(work.steps());
    return work.result;
  }

  /// 逐块折叠相邻边距，逐页、逐片及逐行重放；取消不发布已生成页。
  static Future<List<PageContent>?> applyAsync(
    PageIndex index,
    List<PageBlock> blocks, {
    required int spineIndex,
    bool trimTextEdges = false,
    Future<void> Function()? checkpoint,
  }) async {
    final work = _IndexReplay(index, blocks, spineIndex, trimTextEdges);
    await _consumeIndexStepsAsync(work.steps(), checkpoint);
    return work.result;
  }
}

void _consumeIndexSteps(Iterable<int> steps) {
  for (final _ in steps) {}
}

Future<void> _consumeIndexStepsAsync(
  Iterable<int> steps,
  Future<void> Function()? checkpoint,
) async {
  await checkpoint?.call();
  for (final _ in steps) {
    await checkpoint?.call();
  }
  await checkpoint?.call();
}

class _IndexExtraction {
  _IndexExtraction(this.pagination, this.blocks);

  final ChapterPagination pagination;
  final List<PageBlock> blocks;
  final indexOf = <PageBlock, int>{};
  final entries = <PageIndexEntry>[];

  Iterable<int> steps() sync* {
    for (var i = 0; i < blocks.length; i++) {
      yield 0;
      indexOf[blocks[i]] = i;
    }
    for (final page in pagination.pages) {
      yield 0;
      entries.add(
        PageIndexEntry(
          blockIndex: page.slices.isEmpty
              ? 0
              : indexOf[page.slices.first.block] ?? 0,
          startLine: page.slices.isEmpty ? 0 : page.slices.first.startLine,
          usedHeight: page.usedHeight,
          pageHeight: page.pageHeight,
          topPadding: page.topPadding,
        ),
      );
    }
  }

  PageIndex get result => PageIndex(
    schemaVersion: PageIndex.currentSchemaVersion,
    entries: entries,
  );
}

class _IndexEncoding {
  _IndexEncoding(this.index);

  final PageIndex index;
  late final ByteData data;

  Iterable<int> steps() sync* {
    data = ByteData(
      PageIndex._headerBytes + index.entries.length * PageIndex._entryBytes + 4,
    );
    data.setUint32(0, PageIndex._magic, Endian.big);
    data.setUint16(4, index.schemaVersion, Endian.big);
    data.setUint32(6, index.entries.length, Endian.big);
    var offset = PageIndex._headerBytes;
    var checksum = 0;
    for (final entry in index.entries) {
      yield 0;
      data.setUint32(offset, entry.blockIndex, Endian.big);
      data.setUint32(offset + 4, entry.startLine, Endian.big);
      data.setFloat64(offset + 8, entry.usedHeight, Endian.big);
      data.setFloat64(offset + 16, entry.pageHeight, Endian.big);
      data.setFloat64(offset + 24, entry.topPadding, Endian.big);
      // 单条记录固定 32 字节；大索引在每条记录之间让出预算。
      for (var i = 0; i < PageIndex._entryBytes; i++) {
        checksum = (checksum + data.getUint8(offset + i)) & 0xFFFFFFFF;
      }
      offset += PageIndex._entryBytes;
    }
    data.setUint32(offset, checksum, Endian.big);
  }

  Uint8List get result => data.buffer.asUint8List();
}

class _IndexDecoding {
  _IndexDecoding(this.bytes);

  final Uint8List bytes;
  late final ByteData data;
  int count = 0;
  int checksum = 0;
  final entries = <PageIndexEntry>[];
  PageIndex? result;

  Iterable<int> steps() sync* {
    if (!_readHeader()) return;
    yield* _checksumSteps();
    if (data.getUint32(bytes.length - 4, Endian.big) != checksum) return;
    yield* _entrySteps();
    result = PageIndex(
      schemaVersion: PageIndex.currentSchemaVersion,
      entries: entries,
    );
  }

  bool _readHeader() {
    if (bytes.length < PageIndex._headerBytes + 4) return false;
    data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.big) != PageIndex._magic ||
        data.getUint16(4, Endian.big) != PageIndex.currentSchemaVersion) {
      return false;
    }
    count = data.getUint32(6, Endian.big);
    return bytes.length ==
        PageIndex._headerBytes + count * PageIndex._entryBytes + 4;
  }

  Iterable<int> _checksumSteps() sync* {
    final end = PageIndex._headerBytes + count * PageIndex._entryBytes;
    for (
      var offset = PageIndex._headerBytes;
      offset < end;
      offset += PageIndex._entryBytes
    ) {
      yield 0;
      for (var i = 0; i < PageIndex._entryBytes; i++) {
        checksum = (checksum + bytes[offset + i]) & 0xFFFFFFFF;
      }
    }
  }

  Iterable<int> _entrySteps() sync* {
    var offset = PageIndex._headerBytes;
    for (var i = 0; i < count; i++) {
      yield 0;
      entries.add(
        PageIndexEntry(
          blockIndex: data.getUint32(offset, Endian.big),
          startLine: data.getUint32(offset + 4, Endian.big),
          usedHeight: data.getFloat64(offset + 8, Endian.big),
          pageHeight: data.getFloat64(offset + 16, Endian.big),
          topPadding: data.getFloat64(offset + 24, Endian.big),
        ),
      );
      offset += PageIndex._entryBytes;
    }
  }
}

typedef _IndexPageEnd = ({int block, int line});

class _IndexReplay {
  _IndexReplay(this.index, this.source, this.spineIndex, this.trimTextEdges);

  final PageIndex index;
  final List<PageBlock> source;
  final int spineIndex;
  final bool trimTextEdges;
  final blocks = <PageBlock>[];
  final pages = <PageContent>[];
  List<PageContent>? result;

  Iterable<int> steps() sync* {
    if (index.schemaVersion != PageIndex.currentSchemaVersion ||
        index.entries.isEmpty) {
      return;
    }
    yield* _collapseSteps();
    for (var i = 0; i < index.entries.length; i++) {
      yield 0;
      final end = _pageEnd(i);
      if (end == null) return;
      final page = _IndexReplayPage(
        index.entries[i],
        end,
        blocks,
        trimTextEdges,
      );
      yield* page.steps();
      if (!page.isValid) return;
      pages.add(page.finish(spineIndex, pages.length));
    }
    result = pages;
  }

  Iterable<int> _collapseSteps() sync* {
    int? previousFlow;
    for (var i = 0; i < source.length; i++) {
      yield 0;
      final current = source[i];
      if (current.absolute || previousFlow == null) {
        blocks.add(current);
      } else {
        // 每次只折叠两个在流邻块，复用分页器的边界/最小复制规则。
        final pair = PageBlock.collapseAdjacentMargins([
          blocks[previousFlow],
          current,
        ]);
        blocks[previousFlow] = pair.first;
        blocks.add(pair.last);
      }
      if (!current.absolute) previousFlow = i;
    }
  }

  _IndexPageEnd? _pageEnd(int i) {
    final entry = index.entries[i];
    if (entry.blockIndex < 0 || entry.blockIndex >= blocks.length) return null;
    if (entry.startLine < 0 ||
        entry.startLine > blocks[entry.blockIndex].layout.lineCount) {
      return null;
    }
    final next = i + 1 < index.entries.length ? index.entries[i + 1] : null;
    var endBlock = next?.blockIndex ?? blocks.length - 1;
    if (endBlock < entry.blockIndex || endBlock >= blocks.length) return null;
    var endLine = next == null
        ? blocks[endBlock].layout.lineCount
        : next.startLine;
    if (next != null && endLine == 0) {
      endBlock -= 1;
      if (endBlock < entry.blockIndex) return null;
      endLine = blocks[endBlock].layout.lineCount;
    }
    if (endLine < 0 || endLine > blocks[endBlock].layout.lineCount) return null;
    if (endBlock == entry.blockIndex && endLine <= entry.startLine) return null;
    return (block: endBlock, line: endLine);
  }
}

typedef _IndexLineRange = ({int block, int start, int stop});
typedef _IndexSliceEdges = ({
  double leading,
  double trailing,
  double topTrim,
  double bottomTrim,
});

class _IndexReplayPage {
  _IndexReplayPage(this.entry, this.end, this.blocks, this.trimTextEdges);

  final PageIndexEntry entry;
  final _IndexPageEnd end;
  final List<PageBlock> blocks;
  final bool trimTextEdges;
  final slices = <PageBlockSlice>[];
  double used = 0;
  bool _valid = true;

  Iterable<int> steps() sync* {
    var bi = entry.blockIndex;
    var line = entry.startLine;
    while (true) {
      yield 0;
      final block = blocks[bi];
      final stop = bi == end.block ? end.line : block.layout.lineCount;
      if (stop <= line || stop > block.layout.lineCount) {
        _valid = false;
        return;
      }
      final range = (block: bi, start: line, stop: stop);
      var edges = _edges(block, range);
      var height = edges.leading + edges.trailing;
      for (var l = line; l < stop; l++) {
        yield 0;
        height += block.layout.lines[l].height;
      }
      if (stop == block.layout.lineCount) {
        final remaining =
            entry.pageHeight -
            entry.topPadding -
            used -
            (height - block.trailingExtent + edges.bottomTrim);
        final adjustment =
            block.trailingExtentForPage(remaining) - block.trailingExtent;
        height += adjustment;
        edges = (
          leading: edges.leading,
          trailing: edges.trailing + adjustment,
          topTrim: edges.topTrim,
          bottomTrim: edges.bottomTrim,
        );
      }
      _appendSlice(block, range, edges, height);
      if (bi == end.block) break;
      bi += 1;
      line = 0;
    }
  }

  _IndexSliceEdges _edges(PageBlock block, _IndexLineRange range) {
    final topTrim = trimTextEdges && slices.isEmpty && entry.topPadding >= 0
        ? block.textEdgesAt(range.start).top
        : 0.0;
    final bottomTrim = trimTextEdges && range.block == end.block
        ? block.textEdgesAt(range.stop - 1).bottom
        : 0.0;
    return (
      leading:
          (range.start == 0 ? block.leadingExtent : 0.0) +
          (slices.isEmpty ? block.containerTopInset(range.start) : 0.0) -
          topTrim,
      trailing:
          (range.stop == block.layout.lineCount ? block.trailingExtent : 0.0) +
          (range.block == end.block
              ? block.containerBottomInset(range.stop)
              : 0.0) -
          bottomTrim,
      topTrim: topTrim,
      bottomTrim: bottomTrim,
    );
  }

  void _appendSlice(
    PageBlock block,
    _IndexLineRange range,
    _IndexSliceEdges edges,
    double height,
  ) {
    slices.add(
      PageBlockSlice(
        block: block,
        startLine: range.start,
        endLine: range.stop,
        height: height,
        leadingExtent: edges.leading,
        trailingExtent: edges.trailing,
        leftInset: block.leftInset,
        textTopTrim: edges.topTrim,
        textBottomTrim: edges.bottomTrim,
      ),
    );
    used += height;
  }

  // 保留原有 > 0.01 回退口径，包括 NaN 比较的原语义。
  bool get isValid => _valid && !((used - entry.usedHeight).abs() > 0.01);

  PageContent finish(int spineIndex, int pageIndex) => PageContent(
    spineIndex: spineIndex,
    pageIndex: pageIndex,
    slices: UnmodifiableListView<PageBlockSlice>(slices),
    usedHeight: used,
    pageHeight: entry.pageHeight,
    topPadding: entry.topPadding,
  );
}
