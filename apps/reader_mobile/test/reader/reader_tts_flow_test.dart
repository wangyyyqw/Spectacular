import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_playback_sheet.dart';
import 'package:reader_mobile/reader/reader_tts_text.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/reading_highlight.dart';
import 'package:reader_ui/selection/text_range_geometry.dart';

import '../support/reader_pump.dart';
import '../support/reader_tts_fakes.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets('阅读菜单播放与字词高亮接入，后台暂停保留位置且不自动续播', (tester) async {
    ReaderSettings? saved;
    final (controller: controller, system: system) = await _openPlayback(
      tester,
      settings: const ReaderSettings(
        tts: ReaderTtsSettings(
          voiceName: '已删除音色',
          voiceLocale: 'zh-CN',
          autoTurnPage: false,
        ),
      ),
      onSettingsChanged: (value) => saved = value,
    );
    await tester.tap(find.byKey(const ValueKey('tts-start')));
    await pumpReaderUntilComplete(tester, () => system.spoken.isNotEmpty);
    await tester.pumpAndSettle();
    expect(saved?.tts.hasVoice, isFalse);
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    expect(find.byType(ReaderReadingHighlightLayer), findsWidgets);
    final beforePage = tester.widget<ReaderPage>(find.byType(ReaderPage));
    await system.progress(1, 3);
    await tester.pump();
    expect(controller.highlight.value?.wordStartCfi, isNotNull);
    expect(
      identical(beforePage, tester.widget<ReaderPage>(find.byType(ReaderPage))),
      isTrue,
    );
    final beforePause = controller.highlight.value;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    expect(controller.highlight.value, beforePause);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.snapshot.phase, ReaderTtsPhase.paused);
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-tts')));
    await pumpReaderUntil(tester, find.byKey(const ValueKey('tts-resume')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tts-resume')));
    await pumpReaderUntilComplete(tester, () => system.spoken.length == 2);
    expect(controller.snapshot.phase, ReaderTtsPhase.playing);
    await controller.stop();
    expect(controller.highlight.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续滚动按当前句实际位置跟随，手动滑动解除跟随且正文不重排', (tester) async {
    final (controller: controller, system: system) = await _openPlayback(
      tester,
      settings: const ReaderSettings(pageTurnMode: PageTurnMode.scroll),
      paragraphs: [
        for (var i = 1; i <= 40; i++)
          '第$i段，跟随正文中的真实位置，跨过当前视口后自动显示朗读内容，保留原本的文字排版。',
      ],
    );
    final link = controller.textSource as ReaderTtsReaderLink;
    await tester.tap(find.byKey(const ValueKey('tts-start')));
    await pumpReaderUntilComplete(tester, () => system.spoken.isNotEmpty);
    await tester.pumpAndSettle();
    final generation = link.session.generation;
    final revision = link.session.navigationRevision;
    for (var i = 0; i < 15; i++) {
      final count = system.spoken.length;
      await system.complete();
      await pumpReaderUntilComplete(tester, () => system.spoken.length > count);
    }
    final scroll = tester.state<ContinuousScrollViewState>(
      find.byType(ContinuousScrollView),
    );
    final range = controller.highlight.value!;
    final highlightedPage = tester
        .widgetList<ReaderReadingHighlightLayer>(
          find.byType(ReaderReadingHighlightLayer),
        )
        .map((layer) => layer.page)
        .firstWhere(
          (page) => ReaderTextRangeGeometry.containsPoint(page, range.startCfi),
        );
    final line = ReaderTextRangeGeometry.linesFor(
      highlightedPage,
      startCfi: range.startCfi,
      endCfi: range.endCfi,
    ).first;
    final top = scroll.pageTopOnScreen(highlightedPage)! + line.line.rect.top;
    expect(
      top,
      inInclusiveRange(
        0,
        tester.getSize(find.byType(ContinuousScrollView)).height -
            line.line.rect.height,
      ),
    );
    expect(link.session.generation, generation);
    expect(link.session.navigationRevision, revision);
    expect(link.following, isTrue);
    await tester.drag(find.byType(ContinuousScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(link.following, isFalse);
    await pumpReaderTask(tester, scroll.flushVisiblePosition());
    final position = link.session.progress;
    final count = system.spoken.length;
    await system.complete();
    await pumpReaderUntilComplete(tester, () => system.spoken.length > count);
    expect(link.session.progress, position);
    await controller.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统音色查询失败仍可打开设置并切换离线伴听', (tester) async {
    final (controller: _, system: system) = await _openPlayback(tester);
    system.voicesError = StateError('系统服务不可用');
    await tester.tap(find.byKey(const ValueKey('tts-settings')));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('tts-apply-settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取系统音色，仍可选择离线伴听。'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(SegmentedButton<ReaderTtsMode>, '离线伴听'),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<ReaderTtsMode>>(
            find.byType(SegmentedButton<ReaderTtsMode>),
          )
          .selected,
      {ReaderTtsMode.offline},
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<({ReaderTtsController controller, FakeSystemTts system})> _openPlayback(
  WidgetTester tester, {
  ReaderSettings settings = ReaderSettings.defaults,
  List<String> paragraphs = const ['听书验收正文。'],
  ValueChanged<ReaderSettings>? onSettingsChanged,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final root = Directory.systemTemp.createTempSync('reader-tts-flow-');
  final voices = ReaderTtsVoiceStore(rootDirectory: root);
  final system = FakeSystemTts()..autoComplete = false;
  system.install();
  addTearDown(() {
    system.close();
    voices.close();
    root.deleteSync(recursive: true);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: EpubReaderPage(
        bytes: buildTestEpub(paragraphs: paragraphs),
        bookId: 'tts-flow',
        store: MemoryReaderProgressStore(),
        ttsVoiceStore: voices,
        settings: settings,
        onSettingsChanged: onSettingsChanged,
      ),
    ),
  );
  await pumpReaderUntil(tester, find.byType(ReaderView));
  if (settings.pageTurnMode == PageTurnMode.scroll) {
    await pumpReaderUntilComplete(
      tester,
      () =>
          find.byType(ContinuousScrollView).evaluate().isNotEmpty &&
          find
              .byKey(const ValueKey('continuous-scroll-loading'))
              .evaluate()
              .isEmpty,
    );
  }
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ReaderView));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-tts')));
  await pumpReaderUntil(tester, find.byType(ReaderTtsPlaybackSheet));
  await tester.pumpAndSettle();
  return (
    controller: tester
        .widget<ReaderTtsPlaybackSheet>(find.byType(ReaderTtsPlaybackSheet))
        .controller,
    system: system,
  );
}
