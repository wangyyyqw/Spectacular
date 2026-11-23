import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets('阅读菜单启动听书，失效音色回退默认，进入后台停止', (tester) async {
    final root = Directory.systemTemp.createTempSync('reader-tts-flow-');
    final voices = ReaderTtsVoiceStore(rootDirectory: root);
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final speech = Completer<int>();
    final spoken = <String>[];
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getVoices':
          return [
            {'name': '可用音色', 'locale': 'zh-CN'},
          ];
        case 'speak':
          spoken.add(call.arguments as String);
          return speech.future;
        case 'stop':
          stops++;
      }
      return 1;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      voices.close();
      root.deleteSync(recursive: true);
    });
    ReaderSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(paragraphs: ['听书验收正文。']),
          bookId: 'tts-flow',
          store: MemoryReaderProgressStore(),
          ttsVoiceStore: voices,
          settings: const ReaderSettings(
            tts: ReaderTtsSettings(
              voiceName: '已删除音色',
              voiceLocale: 'zh-CN',
              autoTurnPage: false,
            ),
          ),
          onSettingsChanged: (value) => saved = value,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-tts')));
    await pumpReaderUntil(tester, find.text('听书设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tts-start')));
    await pumpReaderUntilComplete(tester, () => spoken.isNotEmpty);
    expect(saved?.tts.hasVoice, isFalse);
    expect(spoken.single, contains('听书验收正文'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(stops, greaterThan(0));
    speech.complete(1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
