import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/position/book_progress_index.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/text/xhtml_text.dart';

import '../../util/bounded_cache.dart';
import 'book_progress.dart';
import 'book_resources.dart';
import 'chapter_structure.dart';

/// 只管理原文位置、目录和字节进度；不持有页面、字体测量或调度器。
class ChapterPositions {
  ChapterPositions(this.resources, this.structures);
  final BookResources resources;
  final ChapterStructureStore structures;
  final _knownMissing = <int>{};
  final _coordinates = BoundedCache<int, ChapterTextCoordinates>(3);
  final _plainTexts = BoundedCache<int, String>(3);
  BookProgressIndex? _progress;
  List<TocEntry>? _toc;

  int get chapterCount => resources.document.spine.length;
  int get plainTextCacheCount => _plainTexts.length;
  BookProgressIndex get progressIndex =>
      _progress ??= bookProgressIndexFor(resources.document);

  void bindProgressIndex(BookProgressIndex index) {
    if (index.chapterCount != chapterCount) {
      throw ArgumentError('进度索引与章节数量不一致');
    }
    _progress = index;
  }

  bool isMissing(int spine) {
    if (spine < 0 || spine >= chapterCount || _knownMissing.contains(spine)) {
      return true;
    }
    if (!resources.document.isChapterMissing(spine)) return false;
    markMissing(spine);
    return true;
  }

  void markMissing(int spine) {
    if (!_knownMissing.add(spine)) return;
    _progress = null;
    _toc = null;
  }

  AnchorChapter anchorChapter(int spine, double width) =>
      structures.prepared(spine, width).anchor;

  ChapterTextCoordinates _coordinatesFor(int spine, double width) =>
      _preparedCoordinatesFor(spine, width) ??
      (throw StateError('章节尚未准备，请先等待章节准备任务完成'));

  ChapterTextCoordinates? _preparedCoordinatesFor(int spine, double width) {
    final cached = _coordinates[spine];
    if (cached != null) return cached;
    final structure = structures.preparedOrNull(spine, width);
    if (structure == null) return null;
    final result = ChapterTextCoordinates(
      structure.anchor,
      elementCfis: structure.images,
    );
    _coordinates[spine] = result;
    return result;
  }

  double? readingPercentForCfi(String? cfi, double width) {
    if (cfi == null || cfi.isEmpty) return null;
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    if (spine == null || isMissing(spine)) return null;
    if (progressIndex.totalWeight <= 0) return null;
    final ratio = _preparedCoordinatesFor(spine, width)?.ratioFor(cfi);
    return ratio == null ? null : progressIndex.percentOf(spine, ratio);
  }

  bool isValidElementCfi(String cfi, double width) {
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    return spine != null &&
        !isMissing(spine) &&
        _coordinatesFor(spine, width).containsElementCfi(cfi);
  }

  String? cfiForReadingPercent(double percent, double width) {
    final location = progressIndex.locate(percent);
    return location == null
        ? null
        : _coordinatesFor(
            location.spineIndex,
            width,
          ).cfiFor(location.chapterRatio);
  }

  String? cfiForTocEntry(TocEntry entry, double width) {
    if (entry.missing || isMissing(entry.spineIndex)) return null;
    final parsed = structures.prepared(entry.spineIndex, width).parsed;
    final direct = entry.cfi;
    if (direct != null && spineIndexOfCfi(direct) == entry.spineIndex) {
      final serialized = direct.serialize();
      if (serialized.isNotEmpty &&
          (anchorChapter(entry.spineIndex, width).offsetFor(serialized) !=
                  null ||
              parsed.nodeAtCfi(direct) != null)) {
        return serialized;
      }
    }
    final fragment = entry.fragment?.trim();
    if (fragment != null && fragment.isNotEmpty) {
      final cfi = parsed.elementById(fragment)?.cfi.serialize();
      if (cfi != null && cfi.isNotEmpty) return cfi;
    }
    return anchorChapter(entry.spineIndex, width).cfiAt(0);
  }

  // 纸面页眉每次构建都会读取目录，整书缺章检查只在目录失效后执行一次。
  List<TocEntry> get toc => _toc ??= _buildToc();

  List<TocEntry> _buildToc() {
    final represented = <int>{};
    final roots = [
      for (final entry in resources.document.toc)
        _decorateEntry(entry, represented),
    ];
    for (var spine = 0; spine < chapterCount; spine++) {
      if (!isMissing(spine) || represented.contains(spine)) continue;
      var insertAt = 0;
      while (insertAt < roots.length && roots[insertAt].spineIndex < spine) {
        insertAt += 1;
      }
      roots.insert(
        insertAt,
        TocEntry(title: '第 ${spine + 1} 章', spineIndex: spine, missing: true),
      );
      represented.add(spine);
    }
    return List<TocEntry>.unmodifiable(roots);
  }

  TocEntry _decorateEntry(TocEntry entry, Set<int> represented) {
    represented.add(entry.spineIndex);
    return TocEntry(
      title: entry.title,
      spineIndex: entry.spineIndex,
      fragment: entry.fragment,
      children: [
        for (final child in entry.children) _decorateEntry(child, represented),
      ],
      playOrder: entry.playOrder,
      cfi: entry.cfi,
      missing: entry.missing || isMissing(entry.spineIndex),
    );
  }

  /// 搜索采用轻量去标签结果，命中后仍需用原文锚点核验偏移。
  String chapterPlainText(int spine) {
    if (resources.isClosed) return '';
    return _plainTexts.putIfAbsent(spine, () {
      try {
        final xhtml = resources.document.chapterXhtml(spine);
        return xhtml == null ? '' : xhtmlToPlainText(xhtml);
      } catch (_) {
        return '';
      }
    });
  }

  void clearCoordinates() => _coordinates.clear();

  void clearContent() {
    _coordinates.clear();
    _plainTexts.clear();
    _knownMissing.clear();
    _progress = null;
    _toc = null;
  }

  void close() => clearContent();
}
