import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection_layer.dart';

class _Source implements ReaderChapterSource {
  _Source() {
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
                text: 'word ' * 20,
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
  final items = <ReaderAnnotation>[];

  @override
  Future<List<ReaderAnnotation>> list() async => List.of(items);

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
    String? note,
  }) async {
    final now = DateTime.now();
    final item = ReaderAnnotation(
      id: '${items.length}',
      type: type,
      startCfi: startCfi,
      endCfi: endCfi,
      quote: quote,
      color: color,
      style: style,
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
  await tester.tap(find.byKey(const ValueKey('selection-action-note')));
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
final Finder _composerClose = find.byKey(
  const ValueKey<String>('note-composer-close'),
);

Future<_Notes> _showEditor(WidgetTester tester) async {
  final source = _Source();
  final notes = _Notes();
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
  testWidgets('打开笔记编辑层时隐藏选区菜单，关闭后恢复', (tester) async {
    final source = _Source();
    final notes = _Notes();
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

    await tester.tap(find.byKey(const ValueKey('selection-action-note')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-composer-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsNothing,
    );

    await tester.tap(_composerClose);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-composer-sheet')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('selection-action-note')));
    await tester.pumpAndSettle();
    await tester.enterText(_composerInput, '保存后仍可再次打开选区菜单');
    await tester.pump();
    await tester.tap(_composerSave);
    await _finishExit(tester);
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsNothing,
    );

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

  testWidgets('键盘弹出时新建笔记操作栏固定在键盘上方', (tester) async {
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
  });

  testWidgets('目录抽屉可打开笔记页签并展示标注', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'drawer-note',
        type: ReaderAnnotationType.highlight,
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
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('reader-drawer-title')),
          )
          .data,
      '目录',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('drawer-tab-annotations')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('reader-drawer-title')),
          )
          .data,
      '笔记',
    );
    expect(find.text('笔记与高亮'), findsOneWidget);
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

  testWidgets('目录抽屉可批量更换高亮和笔记颜色', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.addAll([
      ReaderAnnotation(
        id: 'drawer-highlight',
        type: ReaderAnnotationType.highlight,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
        quote: '第一条待换色标注',
        color: defaultHighlightColor,
        createdAt: DateTime(2026, 11, 3),
        updatedAt: DateTime(2026, 11, 3),
      ),
      ReaderAnnotation(
        id: 'drawer-note',
        type: ReaderAnnotationType.note,
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
      find.byKey(
        const ValueKey<String>('annotation-batch-color-0xFF90CAF9'),
      ),
    );
    await tester.pumpAndSettle();

    expect(notes.items, hasLength(2));
    expect(
      notes.items.every((item) => item.color == 0xFF90CAF9),
      isTrue,
    );
    expect(find.text('已更换 2 条标注颜色'), findsOneWidget);
  });

  testWidgets('保存笔记后退场无异常，保存最新输入并清除选区', (tester) async {
    final notes = await _showEditor(tester);
    await tester.enterText(find.byType(TextField), '第一版');
    await tester.enterText(find.byType(TextField), '  最终笔记  ');
    await tester.pump();
    await tester.tap(_composerSave);
    await _finishExit(tester);
    expect(notes.items, hasLength(1));
    expect(notes.items.single.type, ReaderAnnotationType.note);
    expect(notes.items.single.note, '最终笔记');
    expect(notes.items.single.quote, 'word');
    expect(find.byType(SelectionLayer), findsNothing);
  });

  testWidgets('已有高亮可补写笔记并转为笔记', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'highlight-to-note',
        type: ReaderAnnotationType.highlight,
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

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-add-note')),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(
      const ValueKey<String>('annotation-note-input'),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
      reason: '点击添加笔记后应直接聚焦输入框',
    );
    await tester.enterText(input, '  补写的高亮笔记  ');
    await tester.pump();
    final save = find.byKey(
      const ValueKey<String>('annotation-save-note'),
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(notes.items.single.type, ReaderAnnotationType.note);
    expect(notes.items.single.note, '补写的高亮笔记');
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsNothing,
    );
    expect(find.text('已添加笔记'), findsOneWidget);
  });

  testWidgets('点击已有笔记可修改正文并保存', (tester) async {
    final source = _Source();
    final notes = _Notes();
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
    final input = find.byKey(
      const ValueKey<String>('annotation-note-input'),
    );
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
    expect(find.text('放弃未保存的笔记修改？'), findsOneWidget);

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

  testWidgets('键盘弹出时标注操作栏固定在键盘上方', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'keyboard-actions',
        type: ReaderAnnotationType.note,
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
      expect(
        rect.bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: '$key 被键盘遮挡',
      );
    }
  });

  testWidgets('修改笔记后换色或样式不会丢失草稿，可一次保存', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'draft-color',
        type: ReaderAnnotationType.note,
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
    expect(find.text('放弃未保存的笔记修改？'), findsNothing);

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
    expect(
      notes.items.single.style,
      ReaderAnnotationStyle.background,
    );

    final save = find.byKey(
      const ValueKey<String>('annotation-save-note'),
    );
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

  testWidgets('删除笔记前确认，取消后保留弹层和正文', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'confirm-remove',
        type: ReaderAnnotationType.note,
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
    expect(find.text('删除这条笔记？'), findsOneWidget);
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
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(notes.items, hasLength(1));
    expect(notes.items.single.type, ReaderAnnotationType.note);
    expect(notes.items.single.note, '待删除笔记');
  });

  testWidgets('仅删除笔记正文时保留高亮并可撤销', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'remove-note-only',
        type: ReaderAnnotationType.note,
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
    expect(find.text('删除笔记正文？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-remove-note-confirm')),
    );
    await tester.pumpAndSettle();

    expect(notes.items, hasLength(1));
    expect(notes.items.single.type, ReaderAnnotationType.highlight);
    expect(notes.items.single.note, isNull);
    expect(find.text('已删除笔记正文，保留高亮'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(notes.items.single.type, ReaderAnnotationType.note);
    expect(notes.items.single.note, '需要保留高亮的笔记');
  });

  for (final action in ['取消', '遮罩', '系统返回']) {
    testWidgets('$action 关闭笔记时确认放弃，可继续编辑且再次打开为空', (tester) async {
      final notes = await _showEditor(tester);
      await tester.enterText(find.byType(TextField), '未保存的草稿');
      await tester.pump();
      switch (action) {
        case '取消':
          await tester.tap(_composerClose);
        case '遮罩':
          await tester.tapAt(const Offset(5, 5));
        case '系统返回':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的笔记？'), findsOneWidget);
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

      await tester.tap(_composerClose);
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的笔记？'), findsOneWidget);
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
      await tester.tap(_composerClose);
      await _finishExit(tester);
      expect(notes.items, isEmpty);
    });
  }

  testWidgets('空白笔记不可保存且保留选区', (tester) async {
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

    await tester.tap(_composerClose);
    await _finishExit(tester);
    expect(find.byType(SelectionLayer), findsOneWidget);
  });

  testWidgets('新的操作提示替换旧的撤销提示', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'replace-toast',
        type: ReaderAnnotationType.note,
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
    expect(find.text('已删除笔记'), findsOneWidget);

    await tester.longPressAt(wordPosition);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-highlight')),
    );
    await tester.pumpAndSettle();

    expect(notes.items.single.type, ReaderAnnotationType.highlight);
    expect(find.text('已高亮'), findsOneWidget);
    expect(find.text('已删除笔记'), findsNothing);
  });

  testWidgets('撤销提示会按设定时长自动消失', (tester) async {
    final source = _Source();
    final notes = _Notes();
    notes.items.add(
      ReaderAnnotation(
        id: 'auto-hide-toast',
        type: ReaderAnnotationType.note,
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
    expect(find.text('已删除笔记'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('已删除笔记'), findsNothing);
    expect(find.text('撤销'), findsNothing);
  });
}
