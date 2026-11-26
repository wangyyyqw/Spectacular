import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';

void main() {
  testWidgets('注释样式菜单显示当前项，切换后收起且取消不改设置', (tester) async {
    var style = ReaderFootnoteStyle.dialog;
    final changes = <ReaderFootnoteStyle>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SettingsPanel(
              section: SettingsSection.settings,
              overrides: ReaderSettingsDefaults.overrides,
              themeId: 'white',
              footnoteStyle: style,
              onFootnoteStyleChanged: (value) {
                changes.add(value);
                setState(() => style = value);
              },
              onOverridesChanged: (_) {},
              onThemeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final entry = find.byKey(const ValueKey('settings-footnote-style'));
    expect(find.text('注释样式'), findsOneWidget);
    expect(
      find.descendant(of: entry, matching: find.text('弹窗')),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(find.descendant(of: entry, matching: find.text('弹窗')))
          .right,
      closeTo(tester.getRect(entry).right - 26, .01),
    );
    expect(find.byType(PopupMenuItem<ReaderFootnoteStyle>), findsNothing);
    for (final next in [
      ReaderFootnoteStyle.bubble,
      ReaderFootnoteStyle.paper,
    ]) {
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<ReaderFootnoteStyle>), findsNWidgets(3));
      final selected = find.byKey(
        ValueKey('settings-footnote-style-${style.name}'),
      );
      final text = find.descendant(
        of: selected,
        matching: find.text(style.label),
      );
      expect(
        DefaultTextStyle.of(tester.element(text)).style.color,
        Theme.of(tester.element(entry)).colorScheme.primary,
      );
      await tester.tap(
        find.byKey(ValueKey('settings-footnote-style-${next.name}')),
      );
      await tester.pumpAndSettle();
      expect(style, next);
      expect(find.byType(PopupMenuItem<ReaderFootnoteStyle>), findsNothing);
      expect(
        find.descendant(of: entry, matching: find.text(next.label)),
        findsOneWidget,
      );
    }

    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(style, ReaderFootnoteStyle.paper);
    expect(changes, [ReaderFootnoteStyle.bubble, ReaderFootnoteStyle.paper]);
    expect(find.byType(PopupMenuItem<ReaderFootnoteStyle>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final anchor in [
    const Offset(12, 100),
    const Offset(235, 780),
    const Offset(372, 780),
  ]) {
    testWidgets('屏幕 $anchor 处短气泡等宽居中、纸条宽85%，紧贴注号且可关闭', (tester) async {
      tester.view.physicalSize = const Size(384, 854);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 26, bottom: 24);
      addTearDown(tester.view.reset);
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
                      anchor: anchor,
                      contentWidth: 344,
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
        final callout = find.byKey(
          ValueKey('reader-footnote-callout-${style.name}'),
        );
        final rect = tester.getRect(callout);
        final gap = style == ReaderFootnoteStyle.bubble ? 18.0 : 10.0;
        if (anchor.dy < 400) {
          expect(rect.top, closeTo(anchor.dy + gap, .01));
        } else {
          expect(rect.bottom, closeTo(anchor.dy - gap, .01));
        }
        expect(rect.height, lessThan(120));
        if (style == ReaderFootnoteStyle.bubble) {
          expect(rect.width, closeTo(344, .01));
          expect(rect.left, closeTo(384 - rect.right, .01));
        } else {
          expect(rect.width, closeTo(384 * .85, .01));
          expect(rect.left, 0);
        }
        expect(tester.takeException(), isNull);
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
  }

  for (final screen in [const Size(320, 480), const Size(854, 384)]) {
    for (final style in [
      ReaderFootnoteStyle.bubble,
      ReaderFootnoteStyle.paper,
    ]) {
      testWidgets('$screen 大字号长${style.label}遵守比例上限且可滚动', (tester) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showReaderFootnotePopup(
                    context: context,
                    footnote: PageFootnote(
                      start: 0,
                      end: 1,
                      label: '1',
                      kind: NoteKind.footnote,
                      text: List.generate(
                        20,
                        (index) => '第${index + 1}段长注释。',
                      ).join('\n'),
                    ),
                    style: style,
                    anchor: Offset(screen.width - 30, screen.height - 50),
                    contentWidth: screen.width - 48,
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        final callout = find.byKey(
          ValueKey('reader-footnote-callout-${style.name}'),
        );
        final rect = tester.getRect(callout);
        final bubble = style == ReaderFootnoteStyle.bubble;
        expect(
          rect.bottom,
          closeTo(screen.height - 50 - (bubble ? 18 : 10), .01),
        );
        expect(rect.top, greaterThanOrEqualTo(28));
        expect(
          rect.width,
          closeTo(bubble ? screen.width - 48 : screen.width * .85, .01),
        );
        expect(
          rect.height + (bubble ? 8 : 0),
          closeTo(screen.height * (bubble ? .40 : .15), .01),
        );
        if (bubble) expect(rect.left, closeTo(screen.width - rect.right, .01));
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: callout, matching: find.byType(Scrollable)).first,
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.drag(callout, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(tester.getRect(callout), rect);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('纸条注释从左侧滑入，关闭时反向滑出', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReaderFootnotePopup(
              context: context,
              footnote: const PageFootnote(
                start: 0,
                end: 1,
                label: '1',
                kind: NoteKind.footnote,
                text: '这是一条注释正文。',
              ),
              style: ReaderFootnoteStyle.paper,
              anchor: const Offset(180, 160),
              contentWidth: 360,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    final callout = find.byKey(
      const ValueKey<String>('reader-footnote-callout-paper'),
    );
    final initial = tester.getRect(callout);
    expect(
      find.ancestor(of: callout, matching: find.byType(SlideTransition)),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 110));
    final middle = tester.getRect(callout);
    expect(middle.left, greaterThan(initial.left));

    await tester.pumpAndSettle();
    final settled = tester.getRect(callout);
    expect(settled.left, closeTo(0, .01));

    Navigator.of(tester.element(callout)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(
      find.byKey(const ValueKey<String>('reader-footnote-callout-paper')),
      findsOneWidget,
    );
    expect(tester.getRect(callout).left, lessThan(settled.left));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFootnoteDialog), findsNothing);
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

  testWidgets('气泡与纸条跨路由保留阅读面板取色', (tester) async {
    final sampled = ColorScheme.fromSeed(
      seedColor: const Color(0xff925577),
      brightness: Brightness.dark,
    );
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
          home: ReaderPanelColorScope(
            scheme: sampled,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderFootnotePopup(
                  context: context,
                  footnote: footnote,
                  style: style,
                  anchor: const Offset(180, 160),
                  contentWidth: 344,
                  readerTheme: ReaderTheme.black,
                ),
                child: const Text('打开'),
              ),
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
      expect(background, sampled.surfaceContainerLow);
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
    }
  });
}
