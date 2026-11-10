import 'dart:collection';
import 'dart:typed_data';

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/api.dart' show PageGallery, PageGalleryFrame;
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';

/// 一个完成结果只持有纯布局产物，不持有文档、字体加载器或归档句柄。
class CompletedChapterLayout {
  factory CompletedChapterLayout({
    required String key,
    required int spineIndex,
    required List<PageContent> pages,
    required List<PageBlock> blocks,
    required List<PageBlock> fixedBlocks,
    required PageBackground? background,
    required String fontDependency,
    Uint8List? pageIndex,
  }) {
    final work = _CompletedLayoutWork(pages, blocks, fixedBlocks, background);
    for (final _ in work.steps()) {}
    return work.finish(key, spineIndex, fontDependency, pageIndex);
  }

  const CompletedChapterLayout._({
    required this.key,
    required this.spineIndex,
    required this.pages,
    required this.blocks,
    required this.fixedBlocks,
    required this.background,
    required this.fontDependency,
    required this.pageIndex,
    required this.estimatedBytes,
  });

  /// 沿用同步构造字段，逐引用复制和估算；取消不返回半成品。
  /// 输入在调用完成前由调用者保留，期间不应修改其列表。
  static Future<CompletedChapterLayout> createAsync({
    required String key,
    required int spineIndex,
    required List<PageContent> pages,
    required List<PageBlock> blocks,
    required List<PageBlock> fixedBlocks,
    required PageBackground? background,
    required String fontDependency,
    Uint8List? pageIndex,
    Future<void>? Function()? checkpoint,
  }) async {
    final work = _CompletedLayoutWork(pages, blocks, fixedBlocks, background);
    await checkpoint?.call();
    for (final _ in work.steps()) {
      final waiting = checkpoint?.call();
      if (waiting != null) await waiting;
    }
    await checkpoint?.call();
    return work.finish(key, spineIndex, fontDependency, pageIndex);
  }

  final String key;
  final int spineIndex;
  final List<PageContent> pages;
  final List<PageBlock> blocks;
  final List<PageBlock> fixedBlocks;
  final PageBackground? background;
  final String fontDependency;
  final Uint8List? pageIndex;
  final int estimatedBytes;

  CompletedChapterLayout withPageIndex(Uint8List bytes) =>
      CompletedChapterLayout._(
        key: key,
        spineIndex: spineIndex,
        pages: pages,
        blocks: blocks,
        fixedBlocks: fixedBlocks,
        background: background,
        fontDependency: fontDependency,
        pageIndex: Uint8List.fromList(bytes),
        estimatedBytes:
            estimatedBytes -
            (pageIndex?.lengthInBytes ?? 0) +
            bytes.lengthInBytes,
      );
}

/// 近期结果按完整键复用，最多三项且估算总容量不超过 32MiB。
class ChapterLayoutCache {
  static const maxEntries = 3;
  static const maxBytes = 32 * 1024 * 1024;
  static final recent = ChapterLayoutCache();

  final LinkedHashMap<String, CompletedChapterLayout> _entries =
      LinkedHashMap();
  final Set<String> _replayRequired = {};
  String? _currentKey;
  String? _previousKey;
  int _bytes = 0;

  int get length => _entries.length;
  int get estimatedBytes => _bytes;
  Iterable<CompletedChapterLayout> get entries =>
      List<CompletedChapterLayout>.unmodifiable(_entries.values);

  bool requiresReplay(String key) => _replayRequired.contains(key);

  /// 只改变复用策略，页、块与索引始终由同一完成条目持有。
  void markForReplay(bool Function(CompletedChapterLayout) matches) {
    for (final entry in _entries.values) {
      if (matches(entry)) _replayRequired.add(entry.key);
    }
  }

  void injectPageIndex(String key, Uint8List bytes) {
    final entry = _entries[key];
    if (entry == null) return;
    put(entry.withPageIndex(bytes));
    _replayRequired.add(key);
  }

  CompletedChapterLayout? get(String key, String fontDependency) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (entry.fontDependency != fontDependency) {
      _bytes -= entry.estimatedBytes;
      _replayRequired.remove(key);
      return null;
    }
    _entries[key] = entry;
    return entry;
  }

  void setCurrent(String? key) {
    if (key == _currentKey) return;
    _previousKey = _currentKey;
    _currentKey = key;
  }

  bool put(CompletedChapterLayout entry) {
    if (entry.estimatedBytes > maxBytes) return false;
    final previous = _entries.remove(entry.key);
    _bytes -= previous?.estimatedBytes ?? 0;
    _entries[entry.key] = entry;
    _replayRequired.remove(entry.key);
    _bytes += entry.estimatedBytes;
    _evict();
    return _entries.containsKey(entry.key);
  }

  void _evict() {
    while (_entries.length > maxEntries || _bytes > maxBytes) {
      final oldest = _entries.keys.firstWhere(
        (key) => key != _currentKey && key != _previousKey,
        orElse: () => _entries.keys.firstWhere((key) => key != _currentKey),
      );
      remove(oldest);
    }
  }

  void remove(String key) {
    final entry = _entries.remove(key);
    _replayRequired.remove(key);
    if (entry != null) _bytes -= entry.estimatedBytes;
  }

  void clearNonCurrent() {
    for (final key in _entries.keys.toList()) {
      if (key != _currentKey) remove(key);
    }
    _previousKey = null;
  }

  void clear() {
    _entries.clear();
    _replayRequired.clear();
    _bytes = 0;
    _currentKey = _previousKey = null;
  }
}

/// 遍历完成结果实际持有的布局图，行内载荷和表格也参与身份去重。
/// 字符串按 UTF-16 容量估算；独立图片解码缓存与原生字形内存不在此图中。
int estimateLayoutBytes(
  List<PageContent> pages,
  List<PageBlock> blocks,
  List<PageBlock> fixedBlocks,
) {
  final memory = _LayoutMemoryWork();
  for (final _ in memory.steps([pages, blocks, fixedBlocks])) {}
  return memory.bytes;
}

/// 两种构造入口共用复制和估算步骤，最终只保留已冻结的顶层列表。
class _CompletedLayoutWork {
  _CompletedLayoutWork(
    this.sourcePages,
    this.sourceBlocks,
    this.sourceFixed,
    this.background,
  );

  final List<PageContent> sourcePages;
  final List<PageBlock> sourceBlocks;
  final List<PageBlock> sourceFixed;
  final PageBackground? background;
  final pages = <PageContent>[];
  final blocks = <PageBlock>[];
  final fixed = <PageBlock>[];
  final memory = _LayoutMemoryWork();

  Iterable<int> steps() sync* {
    yield* _copySteps(sourcePages, pages);
    yield* _copySteps(sourceBlocks, blocks);
    yield* _copySteps(sourceFixed, fixed);
    yield* memory.steps([pages, blocks, fixed, ?background]);
  }

  CompletedChapterLayout finish(
    String key,
    int spineIndex,
    String fontDependency,
    Uint8List? pageIndex,
  ) => CompletedChapterLayout._(
    key: key,
    spineIndex: spineIndex,
    pages: UnmodifiableListView(pages),
    blocks: UnmodifiableListView(blocks),
    fixedBlocks: UnmodifiableListView(fixed),
    background: background,
    fontDependency: fontDependency,
    pageIndex: pageIndex,
    estimatedBytes: memory.bytes + (pageIndex?.lengthInBytes ?? 0),
  );
}

Iterable<int> _copySteps<T>(List<T> source, List<T> target) sync* {
  for (final value in source) {
    yield 0;
    target.add(value);
  }
}

/// 只处理已知布局数据；队列避免嵌套内盒造成递归栈溢出或环引用。
class _LayoutMemoryWork {
  final _seen = HashSet<Object>.identity();
  final _pending = ListQueue<Object>();
  int bytes = 0;

  Iterable<int> steps(List<Object> roots) sync* {
    yield* _references(roots);
    while (_pending.isNotEmpty) {
      yield 0;
      final value = _pending.removeFirst();
      if (_seen.add(value)) yield* _visit(value);
    }
  }

  Iterable<int> _references(Iterable<Object?> values) sync* {
    for (final value in values) {
      yield 0;
      if (value != null) _pending.add(value);
    }
  }

  Iterable<int> _visit(Object value) => switch (value) {
    PageContent() => _page(value),
    PageBlock() => _block(value),
    TextLayoutResult() => _text(value),
    LineBox() => _line(value),
    TableRenderSpec() => _table(value),
    ComputedStyle() => _style(value),
    _ => _metadata(value),
  };

  Iterable<int> _metadata(Object value) => switch (value) {
    PageFootnote() => _footnote(value),
    PageGallery() => _add(128, [value.cfi, value.frames]),
    PageGalleryFrame() => _add(64, [value.cfi, value.content, value.imageUrl]),
    InlineImageSpec() => _add(96, [value.url]),
    InlineBoxPlacement() => _add(96, [value.spec]),
    InlineBoxSpec() => _add(128, [value.payload]),
    PageBlockSlice() => _add(192, [value.block]),
    TableCellRender() => _add(256, [value.layout, value.style, value.startCfi]),
    StyledRun() => _add(64, [value.style]),
    _ => _leaf(value),
  };

  Iterable<int> _leaf(Object value) => switch (value) {
    String() => _add(value.length * 2),
    TypedData() => _add(32, [value.buffer]),
    ByteBuffer() => _add(value.lengthInBytes),
    PageBackground() => _add(128, [value.imageUrl]),
    PageContainerFragment() => _add(64, [value.container]),
    PageContainer() => _add(128, [value.style]),
    RubyAnnotation() => _add(64, [value.text, value.style]),
    LineSpacing() => _spacing(value),
    List<Object?>() => _list(value),
    _ => const <int>[],
  };

  Iterable<int> _add(int size, [List<Object?> references = const []]) sync* {
    bytes += size;
    yield* _references(references);
  }

  Iterable<int> _list(List<Object?> values) sync* {
    bytes += 24 + values.length * 8;
    yield* _references(values);
  }

  Iterable<int> _page(PageContent page) sync* {
    bytes += 128;
    yield* _references([page.slices, page.background]);
  }

  Iterable<int> _block(PageBlock block) sync* {
    bytes += 512;
    yield* _references([
      block.layout,
      block.style,
      block.startCfi,
      block.endCfi,
      block.listMarker,
      block.table,
      block.gallery,
      block.containers,
      block.inlineImages,
      block.footnotes,
      block.rubies,
    ]);
  }

  Iterable<int> _text(TextLayoutResult layout) sync* {
    bytes += 256;
    yield* _references([layout.text, layout.lines, layout.runs]);
  }

  Iterable<int> _line(LineBox line) sync* {
    bytes += 192;
    yield* _references([line.inlineBoxes, line.spacing]);
  }

  Iterable<int> _table(TableRenderSpec table) sync* {
    bytes += 128 + (table.columnXs.length + table.rowYs.length) * 8;
    yield* _references(table.cells);
  }

  Iterable<int> _style(ComputedStyle style) sync* {
    bytes += 512 + style.values.length * 32;
    for (final declaration in style.values.entries) {
      yield* _references([declaration.key, declaration.value]);
    }
  }

  Iterable<int> _footnote(PageFootnote note) sync* {
    bytes += 128;
    yield* _references([note.label, note.text, note.imageUrls]);
  }

  Iterable<int> _spacing(LineSpacing spacing) sync* {
    bytes += 96 + spacing.glyphs.length * 96;
    bytes += (spacing.lockedGaps.length + spacing.justifyGaps.length) * 8;
  }
}
