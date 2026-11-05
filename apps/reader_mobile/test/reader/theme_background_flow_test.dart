import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/test_epub.dart';

Uint8List _book() => File('../../test_corpus/basic.epub').readAsBytesSync();

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF557799), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _themeMenu(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-entry-theme')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets('连续切主题和背景保留前次设置', (tester) async {
    final changes = <ReaderSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: _book(),
          bookId: 'theme-flow',
          store: MemoryReaderProgressStore(),
          settings: ReaderSettings.defaults,
          onSettingsChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _themeMenu(tester);
    await _tap(tester, 'settings-theme-sepia');
    await _tap(tester, 'settings-bg-paper');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(changes.last.themeId, 'sepia');
    expect(changes.last.backgroundId, 'paper');
    await _tap(tester, 'settings-theme-black');
    expect(changes.last.themeId, 'black');
    expect(changes.last.backgroundId, 'paper');
  });

  testWidgets('图片取消和加载失败不保存，旧异步请求不覆盖新背景', (tester) async {
    final source = await openTestChapterSource(_book());
    final bytes = (await tester.runAsync(_png))!;
    final oldLoad = Completer<Uint8List>();
    final changes = <String>[];
    late ReaderSession session;
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            bookId: 'image-race',
            store: MemoryReaderProgressStore(),
            backgroundId: 'image:old',
            onSessionReady: (value) => session = value,
            backgroundImageLoader: (id) => id == 'image:old'
                ? oldLoad.future
                : Future.value(Uint8List.fromList([1, 2, 3])),
            onPickBackgroundImage: () async => picked,
            onBackgroundChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fingerprint = session.layoutFingerprint;
    final position = session.progress;
    await _themeMenu(tester);
    await _tap(tester, 'settings-background-image');
    await tester.pumpAndSettle();
    expect(changes, isEmpty, reason: '取消不保存');
    picked = 'image:broken';
    await _tap(tester, 'settings-background-image');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(changes, isEmpty, reason: '损坏图片不保存');
    await _tap(tester, 'settings-bg-none');
    await tester.pumpAndSettle();
    oldLoad.complete(bytes);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(changes, ['none']);
    expect(find.text('图片背景已启用'), findsNothing, reason: '过期图片不回写');
    expect(session.layoutFingerprint, fingerprint);
    expect(session.progress, position);
    expect(tester.takeException(), isNull);
  });
  testWidgets('恢复缺失图片时回退纯色，不显示已启用图片', (tester) async {
    final source = await openTestChapterSource(_book());
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            bookId: 'missing-background',
            store: MemoryReaderProgressStore(),
            backgroundId: 'image:missing',
            backgroundImageLoader: (_) async =>
                throw const FormatException('文件缺失'),
            onBackgroundChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _themeMenu(tester);
    expect(find.text('图片背景已启用'), findsNothing);
    expect(changes, isEmpty, reason: '恢复失败不会保存无效图片');
    expect(tester.takeException(), isNull);
  });
}
