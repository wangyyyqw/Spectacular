import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_editor_sheet.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/annotations/decorations.dart';
import 'package:reader_ui/annotations/note_composer_sheet.dart';
import 'package:reader_ui/annotations/thought_marker.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/panels/annotation_panel.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_core/source/chapter_source.dart';

class _Source implements ReaderChapterSource {
  _Source({String? text}) {
    final style = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    pages = Paginator(pageHeight: 300)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: TextLayoutEngine.layout(
                text: text ?? 'word ' * 20,
                style: style,
                maxWidth: 240,
              ),
              style: style,
              containingWidth: 240,
              startCfi: 'epubcfi(/6/2!/4/2/1:0)',
            ),
          ],
        )
        .pages;
  }

  late final List<PageContent> pages;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

class _Notes implements ReaderAnnotationStore {
  _Notes(this.source);

  final _Source source;
  final items = <ReaderAnnotation>[];

  @override
  Future<List<ReaderAnnotation>> list() async => [
    for (final item in items) _withContentEvidence(item),
  ];

  ReaderAnnotation _withContentEvidence(ReaderAnnotation item) {
    final block = source.pages.first.slices.first.block;
    final book = AnchorBook(
      revision: 'reader-layout',
      chapters: [
        AnchorChapter(
          spineIndex: 0,
          href: '',
          blocks: [AnchorBlock(cfi: block.startCfi!, text: block.layout.text)],
        ),
      ],
    );
    final anchor = book.capture(item.startCfi, endCfi: item.endCfi);
    // 编辑回归的记录来自当前文件；只有原引用确实相同时才补有效证据。
    if (anchor == null || anchor.quote != item.quote) return item;
    return ReaderAnnotation(
      id: item.id,
      type: item.type,
      startCfi: item.startCfi,
      endCfi: item.endCfi,
      quote: item.quote,
      contextBefore: item.contextBefore,
      contextAfter: item.contextAfter,
      color: item.color,
      style: item.style,
      opacity: item.opacity,
      note: item.note,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      anchorData: AnchorRecord(original: anchor).encode(),
      relocationStatus: 'verified',
    );
  }

  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    double? opacity,
    String? note,
  }) async {
    final existingIndex = items.indexWhere(
      (item) => item.startCfi == startCfi && item.endCfi == endCfi,
    );
    if (existingIndex >= 0) {
      final existing = items[existingIndex];
      await update(
        existing.id,
        type: existing.type == ReaderAnnotationType.thought
            ? ReaderAnnotationType.thought
            : type,
        color: color,
        style: style,
        opacity: opacity,
        note: type == ReaderAnnotationType.thought ? note : null,
      );
      return items[existingIndex];
    }
    final now = DateTime.now();
    final item = ReaderAnnotation(
      id: '${items.length}',
      type: type,
      startCfi: startCfi,
      endCfi: endCfi,
      quote: quote,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      color: color,
      style: style,
      opacity: opacity,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    double? opacity,
    String? note,
    bool clearNote = false,
  }) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    final old = items[index];
    items[index] = ReaderAnnotation(
      id: old.id,
      type: type ?? old.type,
      startCfi: old.startCfi,
      endCfi: old.endCfi,
      quote: old.quote,
      contextBefore: old.contextBefore,
      contextAfter: old.contextAfter,
      color: color ?? old.color,
      style: style ?? old.style,
      opacity: opacity ?? old.opacity,
      note: clearNote ? null : note ?? old.note,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> remove(String id) async =>
      items.removeWhere((item) => item.id == id);
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('selection-action-thought')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('note-composer-sheet')),
    findsOneWidget,
  );
  expect(find.byType(TextField), findsOneWidget);
}

final Finder _composerInput = find.byKey(
  const ValueKey<String>('note-composer-input'),
);
final Finder _composerSave = find.byKey(
  const ValueKey<String>('note-composer-save'),
);
Future<void> _dismissComposer(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

Future<_Notes> _showEditor(WidgetTester tester) async {
  final source = _Source();
  final notes = _Notes(source);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          annotations: notes,
          bookId: 'note-dialog',
          padding: EdgeInsets.zero,
          overrides: const ReaderOverrides(),
          showPageFooter: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final line = TextHitTester.lineBoxes(source.pages.first).first;
  final wordPosition =
      tester.getTopLeft(find.byType(ReaderView)) +
      Offset(line.rect.left + 6, line.rect.center.dy);
  await tester.longPressAt(wordPosition);
  await tester.pumpAndSettle();
  await _openEditor(tester);
  return notes;
}

Future<void> _finishExit(WidgetTester tester) async {
  // 逐帧检查退场阶段；只检查动画结束会漏掉控制器提前释放的异常。
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.pump(const Duration(milliseconds: 75));
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(
    find.byKey(const ValueKey<String>('note-composer-sheet')),
    findsNothing,
  );
  expect(find.byType(ReaderPage), findsOneWidget);
}

void main() {
  testWidgets('打开想法编辑层时隐藏选区菜单，关闭后恢复', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-hide-selection-menu',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    await tester.longPressAt(
      tester.getTopLeft(find.byType(ReaderView)) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('selection-action-thought')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-composer-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('selection-menu')), findsNothing);

    await _dismissComposer(tester);
    expect(
      find.byKey(const ValueKey<String>('note-composer-sheet')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('selection-action-thought')));
    await tester.pumpAndSettle();
    await tester.enterText(_composerInput, '保存后仍可再次打开选区菜单');
    await tester.pump();
    await tester.tap(_composerSave);
    await _finishExit(tester);
    expect(find.byKey(const ValueKey<String>('selection-menu')), findsNothing);

    await tester.longPressAt(
      tester.getTopLeft(find.byType(ReaderView)) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );
  });

  testWidgets('键盘弹出时新建想法操作栏固定在键盘上方', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _showEditor(tester);
    await tester.enterText(_composerInput, '键盘弹出后仍需看见保存按钮');
    tester.view.viewInsets = const FakeViewPadding(bottom: 1500);
    await tester.pumpAndSettle();

    final rect = tester.getRect(_composerSave);
    expect(rect.top, greaterThanOrEqualTo(0), reason: '保存按钮顶部不可见');
    expect(rect.bottom, lessThanOrEqualTo(300), reason: '保存按钮被键盘遮挡');
    expect(tester.takeException(), isNull);
  });

  testWidgets('目录抽屉可打开标注页签并展示划线', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'drawer-note',
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: '抽屉里的高亮原文',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'annotation-drawer',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    expect(find.byType(TocPanel), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('drawer-tab-annotations')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TocPanel), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AnnotationPanel),
        matching: find.text('标注'),
      ),
      findsOneWidget,
    );
    expect(find.text('抽屉里的高亮原文'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-row-drawer-note')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('drawer-tab-annotations')),
      findsNothing,
    );
  });

  testWidgets('目录抽屉可批量更换划线和想法颜色', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.addAll([
      ReaderAnnotation(
        id: 'drawer-highlight',
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: '第一条待换色标注',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
      ReaderAnnotation(
        id: 'drawer-note',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:5)',
        endCfi: 'epubcfi(/6/2!/4/2/1:9)',
        quote: '第二条待换色标注',
        note: '一起换色',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'annotation-recolor',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('drawer-tab-annotations')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-manage')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-select-all')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-recolor')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-color-0xFF90CAF9')),
    );
    await tester.pumpAndSettle();

    expect(notes.items, hasLength(2));
    expect(notes.items.every((item) => item.color == 0xFF90CAF9), isTrue);
    expect(find.text('已更换 2 条标注颜色'), findsNothing);
  });

  testWidgets('保存想法后退场无异常，保存最新输入并清除选区', (tester) async {
    final notes = await _showEditor(tester);
    await tester.enterText(find.byType(TextField), '第一版');
    await tester.enterText(find.byType(TextField), '  最终笔记  ');
    await tester.pump();
    await tester.tap(_composerSave);
    await _finishExit(tester);
    expect(notes.items, hasLength(1));
    expect(notes.items.single.type, ReaderAnnotationType.thought);
    expect(notes.items.single.note, '最终笔记');
    expect(notes.items.single.quote, 'word');
    expect(find.byType(SelectionLayer), findsNothing);
  });

  testWidgets('同区间快捷划线保留原想法，撤销恢复样式与透明度', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'same-range-thought',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '快捷划线不能删除这条想法',
        color: 0xFF90CAF9,
        style: ReaderAnnotationStyle.wavyUnderline,
        opacity: 0.41,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'same-range-thought',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);
    await tester.longPressAt(wordPosition);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-mark')),
    );
    await tester.pumpAndSettle();
    expect(notes.items, hasLength(1));
    expect(notes.items.single.id, 'same-range-thought');
    expect(notes.items.single.type, ReaderAnnotationType.thought);
    expect(notes.items.single.note, '快捷划线不能删除这条想法');
    expect(notes.items.single.style, ReaderAnnotationStyle.underline);
    expect(notes.items.single.color, defaultHighlightColor);
    expect(notes.items, hasLength(1));
    expect(notes.items.single.style, ReaderAnnotationStyle.underline);
    expect(notes.items.single.color, defaultHighlightColor);
    expect(notes.items.single.opacity, 0.41);
    expect(notes.items.single.note, '快捷划线不能删除这条想法');
    await tester.longPressAt(wordPosition);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-thought')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReaderAnnotationEditorSheet), findsOneWidget);
    expect(find.byType(ReaderNoteComposerSheet), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('annotation-note-input')),
          )
          .controller
          ?.text,
      '快捷划线不能删除这条想法',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有划线可补写想法并升级同一记录', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'highlight-to-note',
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'highlight-to-note',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-note-input')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('annotation-add-note')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey<String>('annotation-note-input'));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
      reason: '点击添加想法后应直接聚焦输入框',
    );
    await tester.enterText(input, '  补写的高亮笔记  ');
    await tester.pump();
    final save = find.byKey(const ValueKey<String>('annotation-save-note'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(notes.items.single.type, ReaderAnnotationType.thought);
    expect(notes.items.single.note, '补写的高亮笔记');
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsNothing,
    );
    expect(find.text('已添加想法'), findsNothing);
  });

  testWidgets('墨水屏编辑划线时不显示无效的颜色选项', (tester) async {
    final annotation = ReaderAnnotation(
      id: 'ink-editor',
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/2!/4/2/1:0)',
      endCfi: 'epubcfi(/6/2!/4/2/1:4)',
      quote: 'word',
      color: defaultHighlightColor,
      createdAt: DateTime(2026, 11, 4),
      updatedAt: DateTime(2026, 11, 4),
    );
    Widget sheet({required bool inkMode}) => MaterialApp(
      home: Scaffold(
        body: ReaderAnnotationEditorSheet(
          annotation: annotation,
          inkMode: inkMode,
        ),
      ),
    );

    await tester.pumpWidget(sheet(inkMode: true));
    expect(
      find.byKey(const ValueKey<String>('annotation-ink-color-hint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-color-0xFFFFEB3B')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-style-wavyUnderline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-style-background')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-style-underline')),
      findsOneWidget,
    );

    await tester.pumpWidget(sheet(inkMode: false));
    expect(
      find.byKey(const ValueKey<String>('annotation-ink-color-hint')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-color-0xFFFFEB3B')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-style-background')),
      findsOneWidget,
    );
  });

  testWidgets('墨水屏新建想法预览使用黑色下划线', (tester) async {
    Widget sheet({required bool inkMode}) => MaterialApp(
      home: Scaffold(
        body: ReaderNoteComposerSheet(quote: 'word', inkMode: inkMode),
      ),
    );

    await tester.pumpWidget(sheet(inkMode: true));
    expect(
      find.byKey(const ValueKey<String>('note-composer-ink-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('note-composer-quote-preview')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('line-tab')), findsOneWidget);
    for (final section in ['color', 'background', 'width']) {
      expect(find.byKey(ValueKey<String>('$section-tab')), findsNothing);
    }
    expect(
      find.byKey(const ValueKey<String>('annotation-style-underline')),
      findsOneWidget,
    );

    await tester.pumpWidget(sheet(inkMode: false));
    expect(
      find.byKey(const ValueKey<String>('note-composer-quote-preview')),
      findsOneWidget,
    );
  });

  testWidgets('点击页边想法图标打开编辑层', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'note-marker',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '点击圆点打开',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-marker',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final markerCenter = ThoughtMarkerGeometry.markersFor(
      source.pages.first,
      AnnotationDecorations.linesFor(source.pages.first, notes.items),
      contentWidth: tester.getSize(find.byType(AnnotationLayer)).width,
    ).single.center;

    await tester.tapAt(
      tester.getTopLeft(find.byType(AnnotationLayer)) + markerCenter,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-note-input')),
      findsOneWidget,
    );
  });

  testWidgets('点击已有想法可修改正文并保存', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-edit',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);

    await tester.longPressAt(wordPosition);
    await tester.pumpAndSettle();
    await _openEditor(tester);
    await tester.enterText(find.byType(TextField), '第一版笔记');
    await tester.pump();
    await tester.tap(_composerSave);
    await _finishExit(tester);
    expect(notes.items.single.note, '第一版笔记');

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    final input = find.byKey(const ValueKey<String>('annotation-note-input'));
    expect(tester.widget<TextField>(input).controller?.text, '第一版笔记');

    await tester.enterText(input, '  更新后的笔记  ');
    await tester.pump();
    final save = find.byKey(const ValueKey<String>('annotation-save-note'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(notes.items.single.note, '更新后的笔记');
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsNothing,
    );

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    final reopenedInput = find.byKey(
      const ValueKey<String>('annotation-note-input'),
    );
    await tester.enterText(reopenedInput, '未保存的修改');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的想法修改？'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-discard-cancel')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reopenedInput).controller?.text, '未保存的修改');

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-discard-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsNothing,
    );
    expect(notes.items.single.note, '更新后的笔记');
  });

  testWidgets('连续滚动模式下滚动后点击想法图标可打开编辑层', (tester) async {
    final source = _Source(text: 'word ' * 160);
    final notes = _Notes(source);
    const start = 700;
    const end = 704;
    PageContent? targetPage;
    PageLineBox? targetLine;
    for (final page in source.pages) {
      for (final line in TextHitTester.lineBoxes(page)) {
        if (line.blockTextOffset <= start &&
            line.blockTextOffset + line.text.length >= end) {
          targetPage = page;
          targetLine = line;
          break;
        }
      }
      if (targetLine != null) break;
    }
    expect(targetPage, isNotNull);
    expect(targetLine, isNotNull);
    final page = targetPage!;
    final annotationStartCfi = 'epubcfi(/6/2!/4/2/1:$start)';
    final annotationEndCfi = 'epubcfi(/6/2!/4/2/1:$end)';
    notes.items.add(
      ReaderAnnotation(
        id: 'note-marker-scroll',
        type: ReaderAnnotationType.thought,
        startCfi: annotationStartCfi,
        endCfi: annotationEndCfi,
        quote: 'word',
        note: '连续滚动圆点',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-marker-scroll',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pageFinder = find.byKey(
      ValueKey<String>('scroll-page-${page.spineIndex}-${page.pageIndex}'),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    final offsetBeforeScroll = position.pixels;
    await tester.scrollUntilVisible(
      pageFinder,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(offsetBeforeScroll));
    final layer = find.descendant(
      of: pageFinder,
      matching: find.byType(AnnotationLayer),
    );
    final rendered = tester.widget<AnnotationLayer>(layer);
    final markerCenter = ThoughtMarkerGeometry.markersFor(
      rendered.page,
      AnnotationDecorations.linesFor(rendered.page, rendered.annotations),
      contentWidth: tester.getSize(layer).width,
    ).single.center;

    await tester.tapAt(tester.getTopLeft(layer) + markerCenter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('连续滚动长按下方页面时选区与想法引用命中该页', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final text = List.generate(240, (index) => 'word$index').join(' ');
    final source = _Source(text: text);
    final notes = _Notes(source);
    expect(source.pages, hasLength(greaterThan(1)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'scroll-selection-below-fold',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const firstPageKey = ValueKey<String>('scroll-page-0-0');
    const secondPageKey = ValueKey<String>('scroll-page-0-1');
    final firstPage = find.byKey(firstPageKey);
    final secondPage = find.byKey(secondPageKey);
    expect(firstPage, findsOneWidget);
    expect(secondPage, findsOneWidget);

    final firstPageTop = tester.getTopLeft(firstPage).dy;
    final secondPageTop = tester.getTopLeft(secondPage).dy;
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
    scroll.position.jumpTo(
      scroll.position.pixels + (secondPageTop - firstPageTop) * 0.6,
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(ReaderView));
    final scrolledFirstTop = tester.getTopLeft(firstPage).dy;
    final scrolledSecondTop = tester.getTopLeft(secondPage).dy;
    expect(scrolledFirstTop, lessThan(viewport.top));
    expect(scrolledSecondTop, greaterThan(viewport.top));
    expect(scrolledSecondTop, lessThan(viewport.bottom));

    final line = TextHitTester.lineBoxes(source.pages[1]).first;
    final pageTop = tester.getTopLeft(secondPage);
    final localWordPosition = Offset(line.rect.left + 6, line.rect.center.dy);
    await tester.longPressAt(pageTop + localWordPosition);
    await tester.pumpAndSettle();

    final layer = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(layer.pageIndex, 1);

    final hit = TextHitTester.hitTest(source.pages[1], localWordPosition);
    expect(hit, isNotNull);
    final expectedQuote = SelectionOps.textOf(
      source.pages[1],
      SelectionOps.wordAt(source.pages[1], hit!),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-thought')),
    );
    await tester.pumpAndSettle();
    final composer = tester.widget<ReaderNoteComposerSheet>(
      find.byType(ReaderNoteComposerSheet),
    );
    expect(composer.quote, expectedQuote);
  });

  testWidgets('连续滚动用户滚动时取消选区', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = _Source(text: 'word ' * 160);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: _Notes(source),
            bookId: 'scroll-hide-selection-menu',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstPage = find.byKey(const ValueKey<String>('scroll-page-0-0'));
    final line = TextHitTester.lineBoxes(source.pages.first)[2];
    await tester.longPressAt(
      tester.getTopLeft(firstPage) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
    expect(find.byKey(const ValueKey<String>('selection-menu')), findsNothing);
  });

  testWidgets('连续滚动拖到页底不切换内部页码', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = _Source(text: 'word ' * 160);
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: _Notes(source),
            bookId: 'scroll-edge-drag',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
            onSessionReady: (value) => session = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstPage = find.byKey(const ValueKey<String>('scroll-page-0-0'));
    final line = TextHitTester.lineBoxes(source.pages.first)[2];
    await tester.longPressAt(
      tester.getTopLeft(firstPage) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 0);

    final viewport = tester.getRect(find.byType(ReaderView));
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('selection-handle-end')),
      ),
    );
    await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 4));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(session.page?.pageIndex, 0);
    expect(
      tester.widget<SelectionLayer>(find.byType(SelectionLayer)).pageIndex,
      0,
    );
  });

  testWidgets('键盘弹出时标注操作栏固定在键盘上方', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'keyboard-actions',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '键盘弹出时仍需看见操作按钮',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'keyboard-actions',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    await tester.tapAt(
      tester.getTopLeft(find.byType(ReaderView)) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey<String>('annotation-note-input'));
    await tester.showKeyboard(input);
    tester.view.viewInsets = const FakeViewPadding(bottom: 1200);
    await tester.pumpAndSettle();

    const keyboardTop = 400.0;
    for (final key in <String>[
      'annotation-save-note',
      'annotation-remove-note',
      'annotation-remove',
    ]) {
      final rect = tester.getRect(find.byKey(ValueKey<String>(key)));
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$key 顶部不可见');
      expect(rect.bottom, lessThanOrEqualTo(keyboardTop), reason: '$key 被键盘遮挡');
    }
  });

  testWidgets('修改想法后换色或样式不会丢失草稿，可一次保存', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'draft-color',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '旧笔记',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-color-draft',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey<String>('annotation-note-input'));
    await tester.enterText(input, '尚未保存的修改');
    await tester.pump();

    // 点击当前颜色不产生修改。
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-color-0xFFFFEB3B')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect(find.text('放弃未保存的想法修改？'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-color-0xFF90CAF9')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller?.text, '尚未保存的修改');
    expect(notes.items.single.color, defaultHighlightColor);

    final wavyStyle = find.byKey(
      const ValueKey<String>('annotation-style-wavyUnderline'),
    );
    await tester.ensureVisible(wavyStyle);
    await tester.pumpAndSettle();
    await tester.tap(wavyStyle);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller?.text, '尚未保存的修改');
    expect(notes.items.single.style, ReaderAnnotationStyle.background);

    final save = find.byKey(const ValueKey<String>('annotation-save-note'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsNothing,
    );
    expect(notes.items.single.color, 0xFF90CAF9);
    expect(notes.items.single.style, ReaderAnnotationStyle.wavyUnderline);
    expect(notes.items.single.note, '尚未保存的修改');
  });

  testWidgets('删除想法标注前确认，取消后保留弹层和正文', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'confirm-remove',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '待删除笔记',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-remove-confirm',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    final remove = find.byKey(const ValueKey<String>('annotation-remove'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('删除这条标注？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-remove-cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect(notes.items, hasLength(1));

    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-remove-confirm')),
    );
    await tester.pumpAndSettle();
    expect(notes.items, isEmpty);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('仅删除想法正文时保留划线并可撤销', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'remove-note-only',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '需要保留高亮的笔记',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'remove-note-only',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    await tester.tapAt(
      tester.getTopLeft(find.byType(ReaderView)) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();

    final removeNote = find.byKey(
      const ValueKey<String>('annotation-remove-note'),
    );
    await tester.ensureVisible(removeNote);
    await tester.tap(removeNote);
    await tester.pumpAndSettle();
    expect(find.text('只删除这条想法？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-remove-note-confirm')),
    );
    await tester.pumpAndSettle();

    expect(notes.items, hasLength(1));
    expect(notes.items.single.type, ReaderAnnotationType.mark);
    expect(notes.items.single.note, isNull);
    expect(find.text('已删除想法，保留划线'), findsNothing);
  });

  for (final action in ['遮罩', '系统返回', '下滑把手']) {
    testWidgets('$action 关闭想法时确认放弃，可继续编辑且再次打开为空', (tester) async {
      final notes = await _showEditor(tester);
      await tester.enterText(find.byType(TextField), '未保存的草稿');
      await tester.pump();
      switch (action) {
        case '遮罩':
          await tester.tapAt(const Offset(5, 5));
        case '系统返回':
          await tester.binding.handlePopRoute();
        case '下滑把手':
          await tester.drag(
            find.byKey(const ValueKey('reader-drawer-drag-handle')),
            const Offset(0, 100),
          );
      }
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的想法？'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('note-discard-cancel')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('note-composer-sheet')),
        findsOneWidget,
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '未保存的草稿',
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的想法？'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('note-discard-confirm')),
      );
      await _finishExit(tester);
      expect(notes.items, isEmpty);
      expect(find.byType(SelectionLayer), findsOneWidget);
      await _openEditor(tester);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      await tester.tapAt(const Offset(5, 5));
      await _finishExit(tester);
      expect(notes.items, isEmpty);
    });
  }

  testWidgets('空白想法不可保存且保留选区', (tester) async {
    final notes = await _showEditor(tester);
    await tester.enterText(_composerInput, '   ');
    await tester.pump();

    expect(tester.widget<FilledButton>(_composerSave).onPressed, isNull);
    expect(
      find.byKey(const ValueKey<String>('note-composer-sheet')),
      findsOneWidget,
    );
    expect(notes.items, isEmpty);
    expect(find.byType(SelectionLayer), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await _finishExit(tester);
    expect(find.byType(SelectionLayer), findsOneWidget);
  });

  testWidgets('新的操作提示替换旧的撤销提示', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'replace-toast',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '待删除笔记',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'replace-toast',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    final remove = find.byKey(const ValueKey<String>('annotation-remove'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-remove-confirm')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已删除想法及划线'), findsNothing);

    await tester.longPressAt(wordPosition);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-mark')),
    );
    await tester.pumpAndSettle();

    expect(notes.items.single.type, ReaderAnnotationType.mark);
    expect(find.text('已划线'), findsNothing);
    expect(notes.items.single.style, ReaderAnnotationStyle.underline);
    expect(notes.items.single.color, defaultHighlightColor);
    expect(find.text('已删除想法及划线'), findsNothing);
  });

  testWidgets('撤销提示会按设定时长自动消失', (tester) async {
    final source = _Source();
    final notes = _Notes(source);
    notes.items.add(
      ReaderAnnotation(
        id: 'auto-hide-toast',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: 'word',
        note: '待删除笔记',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'auto-hide-toast',
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).first;
    final wordPosition =
        tester.getTopLeft(find.byType(ReaderView)) +
        Offset(line.rect.left + 6, line.rect.center.dy);

    await tester.tapAt(wordPosition);
    await tester.pumpAndSettle();
    final remove = find.byKey(const ValueKey<String>('annotation-remove'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-remove-confirm')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已删除想法及划线'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('已删除想法及划线'), findsNothing);
    expect(find.text('撤销'), findsNothing);
  });
  testWidgets('连续滚动长按下方页面时选区与想法引用命中该页', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final text = List.generate(240, (index) => 'word$index').join(' ');
    final source = _Source(text: text);
    final notes = _Notes(source);
    expect(source.pages, hasLength(greaterThan(1)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'scroll-selection-below-fold',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const firstPageKey = ValueKey<String>('scroll-page-0-0');
    const secondPageKey = ValueKey<String>('scroll-page-0-1');
    final firstPage = find.byKey(firstPageKey);
    final secondPage = find.byKey(secondPageKey);
    expect(firstPage, findsOneWidget);
    expect(secondPage, findsOneWidget);

    final firstPageTop = tester.getTopLeft(firstPage).dy;
    final secondPageTop = tester.getTopLeft(secondPage).dy;
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
    scroll.position.jumpTo(
      scroll.position.pixels + (secondPageTop - firstPageTop) * 0.6,
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(ReaderView));
    final scrolledFirstTop = tester.getTopLeft(firstPage).dy;
    final scrolledSecondTop = tester.getTopLeft(secondPage).dy;
    expect(scrolledFirstTop, lessThan(viewport.top));
    expect(scrolledSecondTop, greaterThan(viewport.top));
    expect(scrolledSecondTop, lessThan(viewport.bottom));

    final line = TextHitTester.lineBoxes(source.pages[1]).first;
    final pageTop = tester.getTopLeft(secondPage);
    final localWordPosition = Offset(line.rect.left + 6, line.rect.center.dy);
    await tester.longPressAt(pageTop + localWordPosition);
    await tester.pumpAndSettle();

    final layer = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(layer.pageIndex, 1);

    final hit = TextHitTester.hitTest(source.pages[1], localWordPosition);
    expect(hit, isNotNull);
    final expectedQuote = SelectionOps.textOf(
      source.pages[1],
      SelectionOps.wordAt(source.pages[1], hit!),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-thought')),
    );
    await tester.pumpAndSettle();
    final composer = tester.widget<ReaderNoteComposerSheet>(
      find.byType(ReaderNoteComposerSheet),
    );
    expect(composer.quote, expectedQuote);
  });

  testWidgets('连续滚动用户滚动时取消选区', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = _Source(text: 'word ' * 160);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: _Notes(source),
            bookId: 'scroll-hide-selection-menu',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstPage = find.byKey(const ValueKey<String>('scroll-page-0-0'));
    final line = TextHitTester.lineBoxes(source.pages.first)[2];
    await tester.longPressAt(
      tester.getTopLeft(firstPage) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
    expect(find.byKey(const ValueKey<String>('selection-menu')), findsNothing);
  });

  testWidgets('连续滚动模式下滚动后点击页边图标可打开想法编辑层', (tester) async {
    final source = _Source(text: 'word ' * 160);
    final notes = _Notes(source);
    const start = 700;
    const end = 704;
    PageContent? targetPage;
    PageLineBox? targetLine;
    for (final page in source.pages) {
      for (final line in TextHitTester.lineBoxes(page)) {
        if (line.blockTextOffset <= start &&
            line.blockTextOffset + line.text.length >= end) {
          targetPage = page;
          targetLine = line;
          break;
        }
      }
      if (targetLine != null) break;
    }
    expect(targetPage, isNotNull);
    expect(targetLine, isNotNull);
    final page = targetPage!;
    final annotationStartCfi = 'epubcfi(/6/2!/4/2/1:$start)';
    final annotationEndCfi = 'epubcfi(/6/2!/4/2/1:$end)';
    notes.items.add(
      ReaderAnnotation(
        id: 'note-marker-scroll',
        type: ReaderAnnotationType.thought,
        startCfi: annotationStartCfi,
        endCfi: annotationEndCfi,
        quote: 'word',
        note: '连续滚动圆点',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: notes,
            bookId: 'note-marker-scroll',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pageFinder = find.byKey(
      ValueKey<String>('scroll-page-${page.spineIndex}-${page.pageIndex}'),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    final offsetBeforeScroll = position.pixels;
    await tester.scrollUntilVisible(
      pageFinder,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(offsetBeforeScroll));
    final layer = find.descendant(
      of: pageFinder,
      matching: find.byType(AnnotationLayer),
    );
    final rendered = tester.widget<AnnotationLayer>(layer);
    final markerCenter = ThoughtMarkerGeometry.markersFor(
      rendered.page,
      AnnotationDecorations.linesFor(rendered.page, rendered.annotations),
      contentWidth: tester.getSize(layer).width,
    ).single.center;

    await tester.tapAt(tester.getTopLeft(layer) + markerCenter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
  });
}
