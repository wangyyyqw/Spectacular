import 'dart:async';

import 'package:reader_core/api.dart' show EpubLayoutType;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/source/chapter_source.dart'
    show ChapterLayoutPriority, ChapterLoadCancelled;
import 'package:reader_core/source/toc.dart' show flattenToc;

import '../../util/bounded_cache.dart';
import 'book_resources.dart';
import 'chapter_anchor_builder.dart';
import 'chapter_image_coordinates.dart';
import 'chapter_preparation_job.dart';
import 'chapter_raw_styles.dart';
import 'chapter_selectors.dart';
import 'chapter_styles.dart';

/// 聚合原文、选择器、锚点与图片分析作为一次纯数据产物交接。
class ChapterStructure {
  const ChapterStructure({
    required this.parsed,
    required this.document,
    required this.selectors,
    required this.anchor,
    required this.footnotes,
    required this.fullBleed,
    required this.fixedFullBleed,
    required this.images,
    required this.sheets,
    required this.fontFamilies,
  });

  /// 宿主共享原始文档和作者表，避免为同步目录消费保存另一份解析树。
  ChapterStructure.withResources(
    ChapterStructure source,
    this.sheets,
    this.parsed,
  ) : document = source.document,
      selectors = source.selectors,
      anchor = source.anchor,
      footnotes = source.footnotes,
      fullBleed = source.fullBleed,
      fixedFullBleed = source.fixedFullBleed,
      images = source.images,
      fontFamilies = source.fontFamilies;
  final ParsedDocument parsed;
  final BlockDocument document;
  final ChapterSelectors selectors;
  final AnchorChapter anchor;
  final Map<String, FootnoteAnchor> footnotes;
  final FullBleedChapter fullBleed;
  final FullBleedChapter fixedFullBleed;
  final List<String> images;
  final List<CssStylesheet> sheets;
  final Set<String> fontFamilies;
}

typedef _StructureConfig = ({
  ComputedStyle baseStyle,
  double width,
  String href,
  String title,
  bool readable,
  bool fixed,
});

class _StructureInput {
  const _StructureInput(this.parsed, this.sheets, this.footnotes, this.config);
  final ParsedDocument parsed;
  final List<CssStylesheet> sheets;
  final Map<String, FootnoteAnchor> footnotes;
  final _StructureConfig config;
}

/// 只保存三章准备数据，关闭后晚到 isolate 结果不能回填。
class ChapterStructureStore {
  ChapterStructureStore(this.resources, this.styles, this.baseStyle);
  static const capacity = 3;
  final BookResources resources;
  final ChapterStyles styles;
  final ComputedStyle baseStyle;
  late final _cache = BoundedCache<String, ChapterStructure>(
    capacity,
    isPinned: (key) => key == _currentKey || key == _visibleKey,
  );
  final _preparing = ChapterPreparationScheduler();
  int preparations = 0;
  int hits = 0;
  bool _closed = false;
  int _epoch = 0;
  String? _currentKey;
  String? _visibleKey;

  int get length => _cache.length;
  Future<void> get preparationsStopped => _preparing.idle;
  String _key(int spine, double width) => '$spine@width=$width';

  /// 实际可见章独立于前台定位请求，避免辅助章准备挤出阅读原文。
  void setCurrentReadingChapter(int spine, double width) {
    _visibleKey = _key(spine, width);
  }

  Future<ChapterStructure> prepare(int spine, double width) =>
      schedule(spine, width).result;

  ChapterPreparationHandle<ChapterStructure> schedule(
    int spine,
    double width, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) {
    if (_closed || resources.isClosed) return cancelledPreparation();
    final key = _key(spine, width);
    if (priority == ChapterLayoutPriority.reading) _currentKey = key;
    final cached = _cached(key);
    if (cached != null) return completedPreparation(cached);
    final epoch = _epoch;
    return _preparing.schedule(
      '$key@$epoch',
      (task) => _prepare(spine, width, key, epoch, task),
      priority: priority,
    );
  }

  ChapterStructure? _cached(String key) {
    if (_closed || resources.isClosed) throw StateError('章节结构已关闭');
    final result = _cache[key];
    if (result != null) hits += 1;
    return result;
  }

  Future<ChapterStructure> _prepare(
    int spine,
    double width,
    String key,
    int epoch,
    PreparationTask task,
  ) async {
    final input = await _prepareInput(spine, width, task);
    _check(epoch, task);
    final prepared = await task.wait(
      resources.preparationWorker.schedule(
        'structure:$key@$epoch',
        () => input,
        _buildStructure,
        priority: task.priority,
      ),
    );
    _check(epoch, task);
    // isolate 传递会复制规则列表；排版沿用仓储的同一作者样式身份，
    // 共享 CSS 的多章才能复用已准备的级联规则。
    final result = ChapterStructure.withResources(
      prepared,
      input.sheets,
      input.parsed,
    );
    preparations += 1;
    _cache[key] = result;
    return result;
  }

  Future<_StructureInput> _prepareInput(
    int spine,
    double width,
    PreparationTask task,
  ) async {
    final parsed = await task.wait(
      resources.scheduleChapter(spine, priority: task.priority),
    );
    final sheets = await task.wait(
      styles.scheduleStylesheets(spine, width: width, priority: task.priority),
    );
    final footnotes = await task.wait(
      resources.scheduleFootnotes(spine, priority: task.priority),
    );
    task.check();
    return _StructureInput(parsed, sheets, footnotes, _config(spine, width));
  }

  void _check(int epoch, PreparationTask task) {
    task.check();
    if (_closed || resources.isClosed || epoch != _epoch) {
      throw const ChapterLoadCancelled();
    }
  }

  /// 同步消费已准备的数据；解析与聚合只由准备任务执行。
  ChapterStructure prepared(int spine, double width) =>
      preparedOrNull(spine, width) ?? (throw StateError('章节尚未准备，请先等待章节准备任务完成'));

  /// 查询准备结果，不在缓存缺失时解压或重解析。
  ChapterStructure? preparedOrNull(int spine, double width) =>
      _cached(_key(spine, width));

  _StructureConfig _config(int spine, double width) {
    final document = resources.document;
    final title =
        flattenToc(document.toc)
            .where((row) => row.entry.spineIndex == spine)
            .firstOrNull
            ?.entry
            .title ??
        '';
    return (
      baseStyle: baseStyle,
      width: width,
      href: document.spine[spine].href,
      title: title,
      readable: !document.progressExcludedSpineIndexes.contains(spine),
      fixed: document.extensionConfig.layout != EpubLayoutType.reflow,
    );
  }

  void clear() {
    _epoch += 1;
    _currentKey = null;
    _visibleKey = null;
    _preparing.cancelAll();
    _cache.clear();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    clear();
    _preparing.close();
  }
}

ChapterStructure _buildStructure(_StructureInput input) {
  final selectors = ChapterSelectors(
    input.parsed.root,
    htmlAttributes: input.parsed.htmlAttributes,
  );
  final raw = ChapterRawStyles(
    selectors,
    input.config.baseStyle,
    input.config.width,
    input.sheets,
  );
  final display = buildAnchorDisplayDocument(input.parsed, input.footnotes);
  final structural = analyzeFullBleed(display);
  final visible = structural.isFullBleed || input.config.fixed
      ? analyzeFullBleed(
          display,
          isRendered: raw.isRendered,
          preserveImageLayout: (node) => _hasImageLayout(raw.styleOf(node)),
        )
      : structural;
  final document = aggregateAnchorDocument(display, raw);
  return ChapterStructure(
    parsed: input.parsed,
    document: document,
    selectors: selectors,
    anchor: AnchorChapter(
      spineIndex: input.parsed.spineIndex,
      href: input.config.href,
      title: input.config.title,
      readable: input.config.readable,
      blocks: collectAnchorBlocks(document, raw),
    ),
    footnotes: input.footnotes,
    fullBleed: structural.isFullBleed ? visible : structural,
    fixedFullBleed: visible,
    images: imageCoordinatesOf(input.parsed.root, raw),
    sheets: List.unmodifiable(input.sheets),
    fontFamilies: Set.unmodifiable(raw.referencedFontFamilies),
  );
}

bool _hasImageLayout(ComputedStyle style) =>
    style.position != CssPosition.static ||
    style.transforms.isNotEmpty ||
    _hasImageSize(style) ||
    style.margin.horizontal != 0 ||
    style.margin.vertical != 0;

bool _hasImageSize(ComputedStyle style) =>
    (style.width != null && !style.width!.isAuto) ||
    (style.height != null && !style.height!.isAuto) ||
    (style.maxWidth != null && style.values['max-width'] != '100%') ||
    style.maxHeight != null;
