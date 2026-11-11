import 'package:path/path.dart' as p;
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/position/book_progress_index.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';

/// 只读取清单与归档元数据，不解压或解析章节。
BookProgressIndex bookProgressIndexFor(EpubDocumentImpl document) {
  final excluded = {...document.progressExcludedSpineIndexes};
  final sizes = <int?>[];
  for (var spine = 0; spine < document.spine.length; spine++) {
    if (document.isChapterMissing(spine)) excluded.add(spine);
    final href = document.spine[spine].href;
    final path = document.resources.resolve(
      href,
      baseDir: p.posix.dirname(document.opfPath),
    );
    sizes.add(document.archive.uncompressedSizeOf(path ?? href));
  }
  return BookProgressIndex.fromUncompressedSizes(sizes, excluded: excluded);
}

/// 单章原文坐标与图片章元素顺序；不依赖字体、行数或页数。
class ChapterTextCoordinates {
  ChapterTextCoordinates(
    this.chapter, {
    Iterable<String> elementCfis = const [],
  }) : elements = List<EpubCfi>.unmodifiable(
         elementCfis.map(EpubCfi.parse).whereType<EpubCfi>(),
       );

  final AnchorChapter chapter;
  final List<EpubCfi> elements;

  double? ratioFor(String cfi) {
    if (chapter.text.isNotEmpty) {
      final offset = chapter.offsetFor(cfi);
      return offset == null ? null : offset / chapter.text.length;
    }
    final key = _elementKey(cfi);
    if (key == null || elements.isEmpty) return null;
    final index = elements.indexWhere(
      (element) => _elementKey(element.serialize()) == key,
    );
    if (index < 0) return null;
    return elements.length == 1 ? 0 : index / (elements.length - 1);
  }

  bool containsElementCfi(String cfi) =>
      chapter.text.isEmpty && ratioFor(cfi) != null;

  String? cfiFor(double ratio) {
    final safe = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0);
    if (chapter.text.isNotEmpty) {
      return chapter.cfiAt(
        (safe * chapter.text.length).round(),
        end: safe == 1,
      );
    }
    if (elements.isEmpty) return null;
    return elements[(safe * (elements.length - 1)).round()].serialize();
  }

  /// 元素位置的省略偏移与 :0 等价；不接受非零字符偏移或范围。
  static String? _elementKey(String value) {
    final cfi = EpubCfi.parse(value);
    if (cfi == null ||
        cfi.isRange ||
        cfi.segments.any(
          (segment) => (segment.offset ?? 0) != 0 || segment.offsetEnd != null,
        )) {
      return null;
    }
    return EpubCfi([
      for (final segment in cfi.segments) CfiSegment(segment.steps),
    ]).serialize();
  }
}
