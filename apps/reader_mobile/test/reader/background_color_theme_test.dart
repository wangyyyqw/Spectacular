import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_background_color_theme.dart';
import 'package:reader_mobile/reader/reader_background_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/theme/theme_color_settings.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../support/reader_pump.dart';

class _Backgrounds extends ReaderBackgroundStore {
  _Backgrounds(this.bytes);
  final Uint8List bytes;
  int loads = 0;
  @override
  Future<Uint8List> load(String id) async {
    loads++;
    return bytes;
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.spectacular.reader_mobile/theme_color'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.spectacular.reader_mobile/theme_color'),
          null,
        );
  });
  testWidgets('阅读背景取色开关只改变面板，正文背景、分页与位置保持', (tester) async {
    final colors = ThemeColorSettings(LibraryStore.memory());
    await colors.initialize();
    addTearDown(colors.dispose);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ThemeColorScope(
          settings: colors,
          child: EpubReaderPage(
            bytes: File('../../test_corpus/basic.epub').readAsBytesSync(),
            bookId: 'background-color-theme',
            store: MemoryReaderProgressStore(),
            settings: ReaderSettings.defaults.copyWithTheme('sepia'),
            onClosed: () => closed = true,
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    final fingerprint = session.layoutFingerprint;
    final progress = session.progress;
    ColorScheme? panelScheme() =>
        ReaderPanelColorScope.maybeOf(tester.element(find.byType(ReaderView)));
    expect(panelScheme(), isNull);
    await colors.setReaderBackgroundEnabled(true);
    await tester.pumpAndSettle();
    expect(panelScheme()!.primary, isNot(ReaderTheme.sepia.text));
    expect(
      tester
          .widget<Scaffold>(find.byKey(const ValueKey('epub-reader-scaffold')))
          .backgroundColor,
      ReaderTheme.sepia.background,
    );
    expect(session.layoutFingerprint, fingerprint);
    expect(session.progress, progress);
    await colors.setReaderBackgroundEnabled(false);
    await tester.pumpAndSettle();
    expect(panelScheme(), isNull);
    expect(session.layoutFingerprint, fingerprint);
    expect(session.progress, progress);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(tester, () => closed);
  });

  testWidgets('图片取色生成配色并复用缓存，深色与关闭选项分别生效', (tester) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xFF228866), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(16, 16);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
    final store = _Backgrounds(bytes!);
    ColorScheme? scheme;
    Future<void> show(ReaderTheme theme, {bool enabled = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderBackgroundColorTheme(
            enabled: enabled,
            theme: theme,
            backgroundId: 'image:test.png',
            store: store,
            child: Builder(
              builder: (context) {
                scheme = ReaderPanelColorScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(ReaderTheme.white);
    final fallback = scheme!.primary;
    await pumpReaderUntilComplete(tester, () => scheme!.primary != fallback);
    final imageScheme = scheme;
    expect(store.loads, 1);
    await show(ReaderTheme.white, enabled: false);
    expect(scheme, isNull);
    await show(ReaderTheme.white);
    expect(scheme, imageScheme);
    expect(store.loads, 1);
    await show(ReaderTheme.black);
    await pumpReaderUntilComplete(
      tester,
      () =>
          scheme!.primary !=
          ColorScheme.fromSeed(
            seedColor: ReaderTheme.black.background,
            brightness: Brightness.dark,
          ).primary,
    );
    expect(scheme!.brightness, Brightness.dark);
    expect(store.loads, 2);
  });
}
