import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  testWidgets('注释样式设置可切换气泡与纸条', (tester) async {
    var style = ReaderFootnoteStyle.dialog;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SettingsPanel(
              section: SettingsSection.settings,
              overrides: ReaderSettingsDefaults.overrides,
              themeId: 'white',
              footnoteStyle: style,
              onFootnoteStyleChanged: (value) => setState(() => style = value),
              onOverridesChanged: (_) {},
              onThemeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('注释样式'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings-footnote-style-bubble')),
    );
    await tester.pumpAndSettle();
    expect(style, ReaderFootnoteStyle.bubble);

    await tester.tap(
      find.byKey(const ValueKey('settings-footnote-style-paper')),
    );
    await tester.pumpAndSettle();
    expect(style, ReaderFootnoteStyle.paper);
  });

  testWidgets('气泡与纸条样式显示注释正文并可点遮罩关闭', (tester) async {
    for (final style in [
      ReaderFootnoteStyle.bubble,
      ReaderFootnoteStyle.paper,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showReaderFootnotePopup(
                    context: context,
                    footnote: const PageFootnote(
                      start: 0,
                      end: 1,
                      label: '1',
                      kind: NoteKind.footnote,
                      text: '这是一条注释正文。',
                    ),
                    style: style,
                    anchor: const Offset(180, 160),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('这是一条注释正文。'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            style == ReaderFootnoteStyle.bubble
                ? 'reader-footnote-callout-bubble'
                : 'reader-footnote-callout-paper',
          ),
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
      expect(find.text('这是一条注释正文。'), findsNothing);
    }
  });

  testWidgets('气泡与纸条样式使用当前面板主题色', (tester) async {
    const scheme = ColorScheme.light(
      surfaceContainerLow: Color(0xFFEFF1EE),
      onSurface: Color(0xFF222427),
      onSurfaceVariant: Color(0xFF686C71),
      outlineVariant: Color(0xFFE4E5E2),
    );
    const footnote = PageFootnote(
      start: 0,
      end: 1,
      label: '1',
      kind: NoteKind.footnote,
      text: '这是一条注释正文。',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: ReaderFootnoteDialog(
            footnote: footnote,
            style: ReaderFootnoteStyle.bubble,
            anchor: Offset(180, 160),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Material>(
            find.byKey(
              const ValueKey<String>('reader-footnote-callout-bubble'),
            ),
          )
          .color,
      scheme.surfaceContainerLow,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: ReaderFootnoteDialog(
            footnote: footnote,
            style: ReaderFootnoteStyle.paper,
            anchor: Offset(180, 160),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PhysicalShape>(
            find.byKey(const ValueKey<String>('reader-footnote-callout-paper')),
          )
          .color,
      scheme.surfaceContainerLow,
    );
  });

  testWidgets('夜间气泡与纸条底色比阅读页背景更浅', (tester) async {
    const footnote = PageFootnote(
      start: 0,
      end: 1,
      label: '1',
      kind: NoteKind.footnote,
      text: '这是一条注释正文。',
    );

    for (final style in [
      ReaderFootnoteStyle.bubble,
      ReaderFootnoteStyle.paper,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReaderFootnotePopup(
                context: context,
                footnote: footnote,
                style: style,
                anchor: const Offset(180, 160),
                readerTheme: ReaderTheme.black,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      final background = style == ReaderFootnoteStyle.bubble
          ? tester
                .widget<Material>(
                  find.byKey(
                    const ValueKey<String>('reader-footnote-callout-bubble'),
                  ),
                )
                .color!
          : tester
                .widget<PhysicalShape>(
                  find.byKey(
                    const ValueKey<String>('reader-footnote-callout-paper'),
                  ),
                )
                .color;
      expect(
        background.computeLuminance(),
        greaterThan(ReaderTheme.black.background.computeLuminance()),
      );
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
    }
  });
}
