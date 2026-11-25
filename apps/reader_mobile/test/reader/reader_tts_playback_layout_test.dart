import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_playback_sheet.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets('听书浮条跟随阅读菜单：菜单收起时隐藏，展开后停在菜单栏上方', (tester) async {
    final root = Directory.systemTemp.createTempSync('reader-tts-layout-');
    final voices = ReaderTtsVoiceStore(rootDirectory: root);
    addTearDown(() {
      voices.close();
      root.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(paragraphs: const ['听书浮条布局测试正文。']),
          bookId: 'tts-playback-layout',
          store: MemoryReaderProgressStore(),
          ttsVoiceStore: voices,
          settings: const ReaderSettings(
            tts: ReaderTtsSettings(mode: ReaderTtsMode.offline),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();

    // 打开听书设置再关掉，拿到阅读页持有的听书控制器。
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-tts')));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('tts-apply-settings')),
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('tts-apply-settings'))),
    ).pop();
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ReaderTtsPlaybackSheet>(find.byType(ReaderTtsPlaybackSheet))
        .controller;
    controller.state.value = const ReaderTtsSnapshot(
      phase: ReaderTtsPhase.playing,
      mode: ReaderTtsMode.offline,
    );
    await tester.pumpAndSettle();

    final sheet = find.byType(ReaderTtsPlaybackSheet);
    final opacity = find.ancestor(
      of: sheet,
      matching: find.byType(AnimatedOpacity),
    );
    final material = tester.widget<Material>(
      find.descendant(of: sheet, matching: find.byType(Material)).first,
    );
    expect(material.elevation, 0);

    // 菜单收起：浮条淡出且不接收点击。
    expect(tester.widget<AnimatedOpacity>(opacity.first).opacity, 0);

    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity.first).opacity, 1);

    final menuSurface = find.byKey(
      const ValueKey('reader-menu-bottom-surface'),
    );
    final openRect = tester.getRect(sheet);
    final openMenuTop = tester.getRect(menuSurface).top;
    expect(openRect.bottom, lessThanOrEqualTo(openMenuTop));

    // 收起菜单后浮条再次隐藏。
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity.first).opacity, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('浮条按钮实心不透明，封面不响应点击，语速按钮分别调旁白与对白语速', (tester) async {
    final root = Directory.systemTemp.createTempSync('reader-tts-speed-');
    final voices = ReaderTtsVoiceStore(rootDirectory: root);
    addTearDown(() {
      voices.close();
      root.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(paragraphs: const ['语速面板测试正文。']),
          bookId: 'tts-speed-panel',
          store: MemoryReaderProgressStore(),
          ttsVoiceStore: voices,
          settings: const ReaderSettings(
            tts: ReaderTtsSettings(mode: ReaderTtsMode.offline),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-tts')));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('tts-apply-settings')),
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('tts-apply-settings'))),
    ).pop();
    await tester.pumpAndSettle();

    final sheet = tester.widget<ReaderTtsPlaybackSheet>(
      find.byType(ReaderTtsPlaybackSheet),
    );
    sheet.controller.state.value = const ReaderTtsSnapshot(
      phase: ReaderTtsPhase.playing,
      mode: ReaderTtsMode.offline,
    );
    await tester.pumpAndSettle();
    // 浮条只在菜单展开时可见。
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();

    final colors = Theme.of(tester.element(find.byType(ReaderTtsPlaybackSheet)))
        .colorScheme;
    final voiceButton = tester.widget<Material>(
      find.byKey(const ValueKey('tts-voice')),
    );
    expect(voiceButton.color, colors.surfaceContainerHighest);
    expect(voiceButton.color!.a, 1);

    final cover = find.byKey(const ValueKey('tts-cover'));
    expect(cover, findsOneWidget);
    expect(
      find.descendant(of: cover, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    final pillRect = tester.getRect(
      find
          .descendant(
            of: find.byType(ReaderTtsPlaybackSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    final coverRect = tester.getRect(cover);
    final cancelRect = tester.getRect(find.byKey(const ValueKey('tts-cancel')));
    expect(
      coverRect.left - pillRect.left,
      closeTo(pillRect.right - cancelRect.right, 0.01),
    );
    expect(find.byTooltip('语速 · 旁白 1.0x · 对白 1.0x'), findsOneWidget);
    expect(
      tester
          .widget<ReaderTtsPlaybackSheet>(find.byType(ReaderTtsPlaybackSheet))
          .speedLabel,
      '语速 · 旁白 1.0x · 对白 1.0x',
    );

    await tester.tap(find.byKey(const ValueKey('tts-speed')));
    await tester.pumpAndSettle();
    expect(find.text('旁白语速'), findsOneWidget);
    expect(find.text('对白语速'), findsOneWidget);

    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tts-speed-apply')));
    await tester.pumpAndSettle();
    expect(find.text('旁白语速'), findsNothing);

    final updated = tester.widget<ReaderTtsPlaybackSheet>(
      find.byType(ReaderTtsPlaybackSheet),
    );
    expect(updated.speedLabel, isNot('语速 · 旁白 1.0x · 对白 1.0x'));
    expect(updated.speedLabel, contains('旁白 '));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
