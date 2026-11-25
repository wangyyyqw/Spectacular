import 'dart:async';

import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reading_highlight.dart';
import 'package:reader_ui/selection/text_range_geometry.dart';

import 'reader_tts_segment.dart';

/// 听书按原文前进，文本来源不依赖屏幕后来显示的页。
abstract interface class ReaderTtsTextSource {
  Future<ReaderTtsTextChunk?> first({required bool autoTurnPage});
  Future<ReaderTtsTextChunk?> next(int spineIndex);
}

/// 一章或启动页内的朗读片段，保留原始 CFI 映射。
class ReaderTtsTextChunk {
  ReaderTtsTextChunk({
    required this.spineIndex,
    required this.segments,
    this.title = '',
    this.chapter,
  });

  final int spineIndex;
  final String title;
  final List<ReaderTtsSegment> segments;
  final AnchorChapter? chapter;

  ReaderTtsTextChunk withShortLead(int startIndex) => ReaderTtsTextChunk(
    spineIndex: spineIndex,
    title: title,
    chapter: chapter,
    segments: ReaderTtsSegmentation.shortenLead(segments, startIndex),
  );

  ReaderReadingHighlight? highlightFor(
    ReaderTtsSegment segment, {
    int? wordStart,
    int? wordEnd,
  }) {
    final anchors = chapter;
    if (anchors == null || segment.text.isEmpty) return null;
    final start = anchors.cfiAt(segment.rawStart(0));
    final end = anchors.cfiAt(segment.rawEnd(segment.text.length), end: true);
    if (start == null || end == null) return null;
    return ReaderReadingHighlight(
      spineIndex: spineIndex,
      startCfi: start,
      endCfi: end,
      wordStartCfi: wordStart == null
          ? null
          : anchors.cfiAt(segment.rawStart(wordStart)),
      wordEndCfi: wordEnd == null
          ? null
          : anchors.cfiAt(segment.rawEnd(wordEnd), end: true),
    );
  }
}

/// 阅读页与独立听书游标的连接；手动导航只解除画面跟随。
class ReaderTtsReaderLink implements ReaderTtsTextSource {
  ReaderTtsReaderLink(this.session) {
    _navigationRevision = session.navigationRevision;
    session.addListener(_checkNavigation);
  }

  final ReaderSession session;
  late int _navigationRevision;
  bool _following = true;
  bool _closed = false;
  bool _screenActive = true;
  bool _catchUp = false;
  Completer<void> _screenSuspended = Completer<void>();
  ReaderReadingHighlight? _target;
  Future<void>? _followingTask;

  bool get following =>
      _following && session.navigationRevision == _navigationRevision;

  void _checkNavigation() {
    if (session.navigationRevision != _navigationRevision) {
      _following = false;
      _navigationRevision = session.navigationRevision;
    }
  }

  @override
  Future<ReaderTtsTextChunk?> first({required bool autoTurnPage}) async {
    final page = session.page;
    if (page == null) return null;
    _following = true;
    _navigationRevision = session.navigationRevision;
    final chapter = await _chapter(page.spineIndex);
    final lines = TextHitTester.lineBoxes(page);
    final startCfi = session.currentCfi;
    final start = startCfi == null ? 0 : chapter.offsetFor(startCfi) ?? 0;
    final last = lines.lastOrNull;
    final endCfi = last?.slice.block.cfiAt(
      last.blockTextOffset + last.text.length,
      end: true,
    );
    final end = !autoTurnPage && endCfi != null
        ? chapter.offsetFor(endCfi) ?? chapter.text.length
        : chapter.text.length;
    final chunk = _chunk(
      chapter,
      start: start,
      end: end,
      pageEnds: autoTurnPage ? await _pageEnds(chapter) : const [],
    );
    return chunk.segments.isNotEmpty
        ? chunk
        : autoTurnPage
        ? next(page.spineIndex)
        : null;
  }

  Future<AnchorChapter> _chapter(int spine) {
    final source = session.source;
    if (source is! AnchorChapterSource) {
      throw StateError('当前书籍无法提供听书原文位置');
    }
    return source.loadAnchorChapter(spine);
  }

  @override
  Future<ReaderTtsTextChunk?> next(int spineIndex) async {
    for (
      var spine = spineIndex + 1;
      spine < session.source.chapterCount;
      spine++
    ) {
      if (_closed) return null;
      final chapter = await _chapter(spine);
      final chunk = _chunk(chapter, pageEnds: await _pageEnds(chapter));
      if (chunk.segments.isNotEmpty) return chunk;
    }
    return null;
  }

  /// 复用当前章分页，以页内最后一行的原文终点切开跨页句段。
  Future<List<int>> _pageEnds(AnchorChapter chapter) async {
    final pages = session.page?.spineIndex == chapter.spineIndex
        ? await session.chapterPages()
        : await session.source.loadChapter(chapter.spineIndex);
    final ends = <int>[];
    for (final page in pages) {
      final last = TextHitTester.lineBoxes(page).lastOrNull;
      final cfi = last?.slice.block.cfiAt(
        last.blockTextOffset + last.text.length,
        end: true,
      );
      final offset = cfi == null ? null : chapter.offsetFor(cfi);
      if (offset != null) ends.add(offset);
    }
    return ends;
  }

  ReaderTtsTextChunk _chunk(
    AnchorChapter chapter, {
    int start = 0,
    int? end,
    Iterable<int> pageEnds = const [],
  }) {
    final segments = <ReaderTtsSegment>[];
    for (final segment in ReaderTtsSegmentation.split(
      chapter.text,
      paragraphStarts: chapter.blockStarts.skip(1),
      pageEnds: pageEnds,
    )) {
      var from = segment.sourceOffsets.indexWhere((offset) => offset >= start);
      if (from < 0) continue;
      from = utf16Boundary(segment.text, from, forward: true);
      var until = end == null
          ? -1
          : segment.sourceOffsets.indexWhere((offset) => offset >= end);
      until = until < 0
          ? segment.text.length
          : utf16Boundary(segment.text, until);
      if (from >= until) continue;
      segments.add(
        ReaderTtsSegment(
          text: segment.text.substring(from, until),
          kind: segment.kind,
          sourceOffsets: segment.sourceOffsets.sublist(from, until),
          continuesOnNextPage:
              segment.continuesOnNextPage && until == segment.text.length,
        ),
      );
    }
    return ReaderTtsTextChunk(
      spineIndex: chapter.spineIndex,
      title: chapter.title,
      segments: segments,
      chapter: chapter,
    );
  }

  /// 只跟随仍属于听书导航的画面；重排后按 CFI 重新计算可见范围。
  Future<void> follow(ReaderReadingHighlight range) {
    _target = range;
    if (_closed || !_screenActive) return Future.value();
    final task = _followingTask ??= _advanceScreen().whenComplete(() {
      _followingTask = null;
    });
    return Future.any([task, _screenSuspended.future]);
  }

  /// 后台只推进原文游标，不等待被系统停止调度的滚动动画。
  Future<void> setScreenActive(bool active) {
    if (_closed || active == _screenActive) return Future.value();
    _screenActive = active;
    if (!active) {
      _screenSuspended.complete();
      return Future.value();
    }
    _screenSuspended = Completer<void>();
    _catchUp = true;
    final target = _target;
    return target == null ? Future.value() : follow(target);
  }

  Future<void> _advanceScreen() async {
    while (!_closed && _screenActive && following) {
      final range = _target;
      final page = session.page;
      if (range == null || page == null || session.loading) return;
      final cfi = range.wordStartCfi ?? range.startCfi;
      if (_catchUp) {
        _catchUp = false;
        if (!ReaderTextRangeGeometry.containsPoint(page, cfi)) {
          if (!await _jumpTo(range)) return;
          continue;
        }
      }
      final scroll = session.revealViewportRange(
        cfi,
        range.wordEndCfi ?? range.endCfi,
      );
      if (scroll != null) {
        await scroll;
        if (!identical(range, _target)) continue;
        return;
      }
      if (ReaderTextRangeGeometry.containsPoint(page, cfi)) return;
      final origin = session.currentCfi;
      if (origin != null &&
          EpubCfi.parse(cfi)!.compareTo(EpubCfi.parse(origin)!) < 0) {
        return;
      }
      if (!await _turnPage()) return;
    }
  }

  Future<bool> _turnPage() async {
    final revision = session.navigationRevision;
    final turn = await session.preparePageTurn(true, prefetch: true);
    if (turn == null) return false;
    if (_closed ||
        !_screenActive ||
        !following ||
        revision != session.navigationRevision) {
      session.releasePageTurn(turn);
      return false;
    }
    _navigationRevision = revision + 1;
    return session.commitPageTurn(turn);
  }

  Future<bool> returnTo(ReaderReadingHighlight range) async {
    _target = range;
    final moved = await _jumpTo(range);
    if (moved) await follow(_target!);
    return moved;
  }

  /// 后台续读直接定位已读到的原文，不逐页补翻或增加阅读统计。
  Future<bool> _jumpTo(ReaderReadingHighlight range) async {
    _following = false;
    final revision = session.navigationRevision + 1;
    _navigationRevision = revision;
    final moved = await session.jumpToCfi(
      range.wordStartCfi ?? range.startCfi,
      title: '朗读位置',
      continuous: session.progress?.scrollOffset != null,
    );
    if (!_closed && moved && session.navigationRevision == revision) {
      _following = true;
    }
    return moved;
  }

  void dispose() {
    _closed = true;
    if (!_screenSuspended.isCompleted) _screenSuspended.complete();
    _following = false;
    session.removeListener(_checkNavigation);
  }
}
