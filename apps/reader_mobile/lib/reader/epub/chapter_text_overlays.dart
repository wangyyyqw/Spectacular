import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/text/reader_text_overlay.dart';

import '../bounded_cache.dart';

/// 覆盖列表冻结一次，只按目标章派生度量指纹，邻章准备不会失效当前章。
class ChapterTextOverlays {
  ChapterTextOverlays(List<ReaderTextOverlay> overlays)
    : _ranges = List.unmodifiable([
        for (final overlay in overlays) ?_ChapterOverlayRange.parse(overlay),
      ]),
      typographyFingerprint = ReaderTextOverlayResolver(
        List.unmodifiable(overlays),
        colors: false,
      ).typographyFingerprint;

  final List<_ChapterOverlayRange> _ranges;
  final String typographyFingerprint;
  final _resolvers = BoundedCache<int, ReaderTextOverlayResolver>(3);

  ReaderTextOverlayResolver forSpine(int spine) => _resolvers.putIfAbsent(
    spine,
    () => ReaderTextOverlayResolver([
      for (final range in _ranges)
        if (range.firstSpine <= spine && spine <= range.lastSpine)
          range.overlay,
    ], colors: false),
  );

  Set<String> familiesFor(int spine) => {
    for (final range in _ranges)
      if (range.firstSpine <= spine && spine <= range.lastSpine)
        ?range.overlay.normalizedFontFamily,
  };
}

class _ChapterOverlayRange {
  const _ChapterOverlayRange(this.overlay, this.firstSpine, this.lastSpine);
  final ReaderTextOverlay overlay;
  final int firstSpine;
  final int lastSpine;

  static _ChapterOverlayRange? parse(ReaderTextOverlay overlay) {
    if (!overlay.affectsTypography) return null;
    final start = EpubCfi.parse(overlay.startCfi);
    final end = EpubCfi.parse(overlay.endCfi);
    if (start == null || end == null || start.compareTo(end) >= 0) return null;
    final first = spineIndexOfCfi(start);
    final last = spineIndexOfCfi(end);
    if (first == null || last == null || first > last) return null;
    return _ChapterOverlayRange(overlay, first, last);
  }
}
