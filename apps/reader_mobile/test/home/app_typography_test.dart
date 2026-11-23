import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/home/book_notes_list.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/review_ticket.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../support/test_epub.dart';

class _Library extends LibraryStore {
  _Library() : super.memory();

  @override
  Future<Map<String, BookNoteCounts>> bookNoteCounts() async => {
    for (final book in await list())
      book.id: (thoughts: 1, marks: 2, updatedAt: DateTime(2026, 11, 20)),
  };

  @override
  Future<Set<String>> finishedBookIds() async => {
    for (final book in await list()) book.id,
  };
}

TextStyle _style(WidgetTester tester, Finder text) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first,
    )
    .text
    .style!;

Future<void> _select(WidgetTester tester, String label) async {
  final navigation = find.byType(NavigationRail).evaluate().isEmpty
      ? find.byType(BottomNavigationBar)
      : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: navigation, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '墨屿',
      packageName: 'com.spectacular.reader_mobile',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    '各页主要文字与书架一致，辅助文字更小更淡',
    (tester) async {
      final desktop =
          debugDefaultTargetPlatformOverride == TargetPlatform.windows;
      tester.view
        ..physicalSize = desktop ? const Size(1080, 800) : const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final library = _Library();
      final book = await library.importBytes(buildTestEpub(title: '山海之间'));
      await library.setSetting('bookshelf.grid', 'false');

      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(brightness),
            theme: theme,
            home: HomeShell(
              library: library,
              progressStore: MemoryReaderProgressStore(),
              onThemeModeChanged: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final primary = _style(
          tester,
          find.byKey(ValueKey('book-row-title-${book.id}')),
        );
        final secondary = _style(tester, find.text('已读 0 分钟'));
        expect(primary.fontSize, 14);
        expect(primary.fontFamily, AppFonts.defaultFamily);
        expect(secondary.fontSize, 12);
        expect(secondary.color, theme.colorScheme.onSurfaceVariant);
        expect(secondary.color, isNot(primary.color));

        await _select(tester, '统计');
        expect(_style(tester, find.text('图书时长')).fontSize, primary.fontSize);
        await _select(tester, '笔记');
        final notesTitle = find
            .descendant(
              of: find.byType(BookNotesList),
              matching: find.text(book.title),
            )
            .last;
        expect(_style(tester, notesTitle).fontSize, primary.fontSize);
        expect(_style(tester, notesTitle).fontFamily, primary.fontFamily);
        expect(_style(tester, find.text('划线 2')).fontSize, secondary.fontSize);
        await tester.tap(find.byKey(const ValueKey('reviews-tab')));
        await tester.pumpAndSettle();
        final reviewTitle = find
            .descendant(
              of: find.byType(ReviewTicket),
              matching: find.text(book.title),
            )
            .last;
        // 票根书名是视觉主标题，字号大于列表主文字但沿用同一字体。
        expect(
          _style(tester, reviewTitle).fontSize,
          greaterThan(primary.fontSize!),
        );
        expect(_style(tester, reviewTitle).fontFamily, primary.fontFamily);
        await _select(tester, '我的');
        expect(_style(tester, find.text('界面主题')).fontSize, primary.fontSize);
        final mode = find.text('跟随系统');
        expect(_style(tester, mode).fontSize, secondary.fontSize);
        expect(_style(tester, mode).color, secondary.color);
        expect(tester.takeException(), isNull);
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('阅读面板继承界面字号，主次文字随阅读配色更新', (tester) async {
    for (final readerTheme in [ReaderTheme.white, ReaderTheme.black]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(fontFamily: 'user_test_font'),
          home: ReaderPanelTheme(
            theme: readerTheme,
            child: const Scaffold(
              body: ListTile(title: Text('阅读面板主文字'), subtitle: Text('阅读面板说明')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final primary = _style(tester, find.text('阅读面板主文字'));
      final secondary = _style(tester, find.text('阅读面板说明'));
      expect(primary.fontSize, 14);
      expect(primary.fontFamily, 'user_test_font');
      expect(secondary.fontFamily, 'user_test_font');
      expect(primary.color, readerTheme.text);
      expect(secondary.fontSize, 12);
      expect(
        secondary.color,
        Color.alphaBlend(readerTheme.sub, readerTheme.background),
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('日夜辅助文字在页面和控件背景上保持可读对比度', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness: brightness);
      expect(
        theme.appBarTheme.titleTextStyle?.fontFamily,
        AppFonts.defaultFamily,
      );
      expect(
        theme.bottomNavigationBarTheme.selectedLabelStyle?.fontFamily,
        AppFonts.defaultFamily,
      );
      final text = theme.textTheme.bodySmall!.color!.computeLuminance();
      for (final surface in [
        theme.colorScheme.surface,
        theme.colorScheme.surfaceContainerLow,
        theme.colorScheme.surfaceContainerHighest,
      ]) {
        final background = surface.computeLuminance();
        final contrast = text > background
            ? (text + .05) / (background + .05)
            : (background + .05) / (text + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    }
  });
}
