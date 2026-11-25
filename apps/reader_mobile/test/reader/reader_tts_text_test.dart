import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_text.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/selection/text_range_geometry.dart';

import '../support/reader_tts_fakes.dart';
import '../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式 EPUB 游标保持段落与原文 CFI，手动跳章不改变听书顺序', () async {
    final source = await openTestChapterSource(
      buildMultiChapterEpub(chapters: ['原序第一句。原序第二句。', '另一个章节。']),
    );
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'tts-navigation',
    );
    await session.open();
    final link = ReaderTtsReaderLink(session);
    final system = FakeSystemTts()..autoComplete = false;
    system.install();
    system.onSpeak = (text) async {
      if (text.startsWith('第 ')) scheduleMicrotask(system.complete);
      return 1;
    };
    final controller = ReaderTtsController(textSource: link)
      ..onPositionChanged = link.follow;
    addTearDown(() async {
      await controller.dispose();
      link.dispose();
      session.dispose();
      source.close();
      system.close();
    });
    final task = controller.start(ReaderTtsSettings.defaults);
    await _until(() => system.spoken.lastOrNull == '原序第一句。');
    final oldRange = controller.highlight.value!;
    expect(
      ReaderTextRangeGeometry.linesFor(
        session.page!,
        startCfi: oldRange.startCfi,
        endCfi: oldRange.endCfi,
      ),
      isNotEmpty,
    );
    await session.jumpToChapter(1);
    expect(link.following, isFalse);
    final revision = session.navigationRevision;
    await system.complete();
    await _until(() => system.spoken.lastOrNull == '原序第二句。');
    expect(session.page!.spineIndex, 1);
    expect(session.navigationRevision, revision);
    final detached = controller.highlight.value!;
    expect(detached.spineIndex, 0);
    expect(
      ReaderTextRangeGeometry.linesFor(
        session.page!,
        startCfi: detached.startCfi,
        endCfi: detached.endCfi,
      ),
      isEmpty,
    );
    expect(await link.returnTo(detached), isTrue);
    expect(link.following, isTrue);
    expect(session.page!.spineIndex, 0);
    expect(
      ReaderTextRangeGeometry.linesFor(
        session.page!,
        startCfi: detached.startCfi,
        endCfi: detached.endCfi,
      ),
      isNotEmpty,
    );
    await controller.stop();
    await task;
  });

  test('重排后仍按 CFI 高亮真实文本，长句跨页只画当前页交集', () async {
    final source = await openTestChapterSource(
      buildTestEpub(paragraphs: ['${'重复' * 120}。']),
      width: 240,
      height: 100,
    );
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'tts-reflow',
    );
    await session.open();
    final link = ReaderTtsReaderLink(session);
    addTearDown(() {
      link.dispose();
      session.dispose();
      source.close();
    });
    final chunk = (await link.first(autoTurnPage: true))!;
    expect(chunk.segments.first.text, '第一章 简单正文');
    final segment = ReaderTtsSegmentation.split(
      chunk.chapter!.text,
      paragraphStarts: chunk.chapter!.blockStarts.skip(1),
    )[1];
    final range = chunk.highlightFor(segment)!;
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final hits = pages
        .where(
          (page) => ReaderTextRangeGeometry.linesFor(
            page,
            startCfi: range.startCfi,
            endCfi: range.endCfi,
          ).isNotEmpty,
        )
        .toList();
    expect(hits.length, greaterThan(1));
    for (final page in hits) {
      for (final line in ReaderTextRangeGeometry.linesFor(
        page,
        startCfi: range.startCfi,
        endCfi: range.endCfi,
      )) {
        expect(
          line.rects.every((rect) => rect.width > 0 && rect.height > 0),
          isTrue,
        );
      }
    }
    await source.applyContentSize(width: 200, height: 100);
    final reflowed = await source.loadChapter(0);
    expect(
      reflowed.any(
        (page) => ReaderTextRangeGeometry.linesFor(
          page,
          startCfi: range.startCfi,
          endCfi: range.endCfi,
        ).isNotEmpty,
      ),
      isTrue,
    );
    expect(
      EpubCfi.parse(range.startCfi)!.compareTo(EpubCfi.parse(range.endCfi)!),
      lessThan(0),
    );
  });

  test('正式分页拆开长句，每段仅在一页内且保留全部原文', () async {
    final playback = await _openBoundaryPlayback();
    final pages = await playback.link.session.source.loadChapter(0);
    final chunk = (await playback.link.first(autoTurnPage: true))!;
    expect(pages.length, greaterThan(2));
    expect(
      chunk.segments.map((segment) => segment.text).join(),
      ReaderTtsSegmentation.split(
        chunk.chapter!.text,
        paragraphStarts: chunk.chapter!.blockStarts.skip(1),
      ).map((segment) => segment.text).join(),
    );
    for (final segment in chunk.segments) {
      final range = chunk.highlightFor(segment)!;
      expect(
        pages.where(
          (page) => ReaderTextRangeGeometry.linesFor(
            page,
            startCfi: range.startCfi,
            endCfi: range.endCfi,
          ).isNotEmpty,
        ),
        hasLength(1),
        reason: '一个离线音频不能包含下一页的文字',
      );
    }
  });

  test('跨页长句在同一音频内翻页，暂停保留音频且下一页接着读', () async {
    final playback = await _openBoundaryPlayback();
    final session = playback.link.session;
    final chunk = (await playback.link.first(autoTurnPage: true))!;
    final last = TextHitTester.lineBoxes(session.page!).last;
    final firstPageEnd = chunk.chapter!.offsetFor(
      last.slice.block.cfiAt(
        last.blockTextOffset + last.text.length,
        end: true,
      )!,
    )!;
    final task = playback.controller.start(_boundarySettings);
    await _until(() => playback.player.clips.isNotEmpty);
    while (playback.player.clips.last.segmentStarts.length == 1) {
      final count = playback.player.clips.length;
      playback.player.complete();
      await _until(() => playback.player.clips.length > count);
    }
    final previous = playback.controller.snapshot.segment!;
    final clip = playback.player.clips.last;
    final count = playback.player.clips.length;
    final boundary = readerTtsDuration(clip.segmentStarts[1], clip.sampleRate);
    playback.player.position(boundary - const Duration(milliseconds: 1));
    expect(session.page!.pageIndex, 0);
    await playback.controller.pause();
    playback.player.position(boundary);
    expect(session.page!.pageIndex, 0);
    await playback.controller.resume();
    playback.player.position(boundary);
    await _until(() => session.page!.pageIndex == 1);
    final current = playback.controller.snapshot.segment!;
    expect(previous.rawEnd(previous.text.length), firstPageEnd);
    expect(current.rawStart(0), firstPageEnd);
    expect(previous.isDialogue, isTrue);
    expect(current.isDialogue, isTrue);
    expect(session.page!.pageIndex, 1);
    expect(playback.player.clips.length, count);
    expect(playback.player.playing, isTrue, reason: '翻页不能结束或重新设置音频');
    expect(playback.link.following, isTrue);
    expect(
      playback.controller.highlight.value?.startCfi,
      chunk.chapter!.cfiAt(firstPageEnd),
    );
    await playback.controller.stop();
    await task;
  });

  test('系统跨页长句只调用一次朗读，实际字词回调翻页', () async {
    final playback = await _openBoundaryPlayback();
    final system = FakeSystemTts()..autoComplete = false;
    system.install();
    addTearDown(system.close);
    system.onSpeak = (text) async {
      if (text.startsWith('第一章')) scheduleMicrotask(system.complete);
      return 1;
    };
    final chunk = (await playback.link.first(autoTurnPage: true))!;
    final last = TextHitTester.lineBoxes(playback.link.session.page!).last;
    final end = chunk.chapter!.offsetFor(
      last.slice.block.cfiAt(
        last.blockTextOffset + last.text.length,
        end: true,
      )!,
    )!;
    final task = playback.controller.start(ReaderTtsSettings.defaults);
    await _until(() => system.spoken.lastOrNull?.startsWith('甲') == true);
    final piece = playback.controller.snapshot.segment!;
    final count = system.spoken.length;
    expect(system.spoken.last.length, greaterThan(piece.text.length));
    final start = end - piece.rawStart(0);
    await system.progress(start, start + 1);
    await _until(() => playback.link.session.page!.pageIndex == 1);
    expect(system.spoken.length, count);
    expect(
      playback.controller.highlight.value?.wordStartCfi,
      chunk.chapter!.cfiAt(end),
    );
    await playback.controller.stop();
    await task;
  });

  test('进入后台解除未完成的滚动等待，后续音频继续且返回跟随最新 CFI', () async {
    final playback = await _openBoundaryPlayback();
    final viewport = Completer<bool>();
    final revealed = <String>[];
    playback.link.session.registerViewportRangeRevealer((start, end) {
      revealed.add(start);
      return viewport.future;
    });
    final task = playback.controller.start(_boundarySettings);
    await _until(() => revealed.isNotEmpty);
    expect(playback.player.clips, isEmpty);
    await playback.link.setScreenActive(false);
    await _until(() => playback.player.clips.length == 1);
    playback.player.complete();
    await _until(() => playback.player.clips.length == 2);
    expect(viewport.isCompleted, isFalse);
    expect(revealed, hasLength(1));
    final latest = playback.controller.position!;
    final resumed = playback.link.setScreenActive(true);
    viewport.complete(true);
    await resumed;
    expect(revealed.last, latest.wordStartCfi ?? latest.startCfi);
    expect(playback.link.following, isTrue);
    expect(playback.player.clips, hasLength(2));
    await playback.controller.stop();
    await task;
  });

  test('后台读过多页返回时直接定位最新句，不逐页追赶或增加翻页统计', () async {
    final playback = await _openBoundaryPlayback();
    final session = playback.link.session;
    final chunk = (await playback.link.first(autoTurnPage: true))!;
    final range = chunk.highlightFor(chunk.segments.last)!;
    final revision = session.navigationRevision;
    final turns = session.pageTurns;
    await playback.link.setScreenActive(false);
    await playback.link.follow(range);
    expect(session.page!.pageIndex, 0);
    await playback.link.setScreenActive(true);
    expect(session.navigationRevision, revision + 1);
    expect(session.pageTurns, turns);
    expect(playback.link.following, isTrue);
    expect(
      ReaderTextRangeGeometry.containsPoint(session.page!, range.startCfi),
      isTrue,
    );
  });

  test('手动翻到其他章节后切后台，返回时不抢走用户的阅读位置', () async {
    final source = await openTestChapterSource(
      buildMultiChapterEpub(chapters: ['听书原文。', '用户手动浏览的章节。']),
    );
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'tts-background-detached',
    );
    await session.open();
    final link = ReaderTtsReaderLink(session);
    addTearDown(() {
      link.dispose();
      session.dispose();
      source.close();
    });
    final chunk = (await link.first(autoTurnPage: true))!;
    final range = chunk.highlightFor(chunk.segments.last)!;
    await session.jumpToChapter(1);
    final revision = session.navigationRevision;
    await link.setScreenActive(false);
    await link.follow(range);
    await link.setScreenActive(true);
    expect(session.page!.spineIndex, 1);
    expect(session.navigationRevision, revision);
    expect(link.following, isFalse);
  });
}

const _boundarySettings = ReaderTtsSettings(
  mode: ReaderTtsMode.offline,
  narratorVoiceId: 'narrator',
  dialogueVoiceId: 'dialogue',
);

Future<
  ({
    ReaderTtsReaderLink link,
    ReaderTtsController controller,
    _BoundarySynthesizer synthesizer,
    _BoundaryPlayer player,
  })
>
_openBoundaryPlayback() async {
  final source = await openTestChapterSource(
    buildTestEpub(paragraphs: ['“${'甲😀乙' * 90}。”结束。']),
    width: 240,
    height: 140,
  );
  final session = ReaderSession(
    source: source,
    store: MemoryReaderProgressStore(),
    bookId: 'tts-page-boundary',
  );
  await session.open();
  final link = ReaderTtsReaderLink(session);
  final synthesizer = _BoundarySynthesizer();
  final player = _BoundaryPlayer();
  final controller = ReaderTtsController(
    textSource: link,
    offlineSynthesizer: synthesizer,
    player: player,
    resolveOfflineVoice: _boundaryVoice,
  )..onPositionChanged = link.follow;
  addTearDown(() async {
    await controller.dispose();
    link.dispose();
    session.dispose();
    source.close();
  });
  return (
    link: link,
    controller: controller,
    synthesizer: synthesizer,
    player: player,
  );
}

Future<ReaderOfflineVoiceInstance?> _boundaryVoice(String id) async =>
    ReaderOfflineVoiceInstance(
      id: id,
      rootPath: '/tmp/$id',
      model: const ReaderOfflineVoiceModel(
        kind: ReaderOfflineModelKind.vits,
        model: 'model.onnx',
        tokens: 'tokens.txt',
      ),
    );

class _BoundarySynthesizer implements ReaderOfflineTtsSynthesizer {
  @override
  Future<void> prepare(ReaderOfflineVoiceInstance voice) async {}

  final segments = <ReaderTtsSegment>[];

  @override
  Stream<ReaderTtsClip> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  }) async* {
    for (final segment in segments) {
      this.segments.add(segment);
      yield pcmTtsClip(
        List.filled(1000, 2000),
        index: this.segments.length - 1,
      );
    }
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _BoundaryPlayer implements ReaderTtsPlayer {
  final clips = <ReaderTtsClip>[];
  Completer<void>? _completion;
  void Function(Duration)? _onPosition;

  bool get playing => _completion?.isCompleted == false;

  @override
  Future<void> play(
    ReaderTtsClip clip, {
    double volume = 1,
    void Function()? onStarted,
    void Function(Duration position)? onPosition,
  }) {
    clips.add(clip);
    _completion = Completer<void>();
    _onPosition = onPosition;
    onStarted?.call();
    return _completion!.future;
  }

  void position(Duration position) => _onPosition?.call(position);

  void complete() {
    if (_completion?.isCompleted == false) _completion!.complete();
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {
    complete();
    _onPosition = null;
  }

  @override
  Future<void> dispose() => stop();
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '预期的朗读原文没有出现');
}
