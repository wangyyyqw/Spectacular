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
    String? note,
  }) async {
    final now = DateTime.now();
    final item = ReaderAnnotation(
      id: '${items.length}',
      type: type,
      startCfi: startCfi,
      endCfi: endCfi,
      quote: quote,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> update(String id, {int? color, String? note}) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    final old = items[index];
    items[index] = ReaderAnnotation(
      id: old.id,
      type: old.type,
      startCfi: old.startCfi,
      endCfi: old.endCfi,
      quote: old.quote,
      contextBefore: old.contextBefore,
      contextAfter: old.contextAfter,
      color: color ?? old.color,
      note: note ?? old.note,
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
  expect(find.byType(TextField), findsOneWidget);
}

Finder _dialogAction(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextButton, label),
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
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(ReaderPage), findsOneWidget);
}

void main() {
  testWidgets('保存笔记后退场无异常，保存最新输入并清除选区', (tester) async {
    final notes = await _showEditor(tester);
    await tester.enterText(find.byType(TextField), '第一版');
    await tester.enterText(find.byType(TextField), '  最终笔记  ');
    await tester.tap(_dialogAction('保存'));
    await _finishExit(tester);
    expect(notes.items, hasLength(1));
    expect(notes.items.single.type, ReaderAnnotationType.note);
    expect(notes.items.single.note, '最终笔记');
    expect(notes.items.single.quote, 'word');
    expect(find.byType(SelectionLayer), findsNothing);
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
    await tester.tap(_dialogAction('保存'));
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
  });

  for (final action in ['取消', '遮罩', '系统返回', '空白保存']) {
    testWidgets('$action 关闭笔记时无异常，不写入标注且再次打开为空', (tester) async {
      final notes = await _showEditor(tester);
      await tester.enterText(
        find.byType(TextField),
        action == '空白保存' ? '   ' : '未保存的草稿',
      );
      switch (action) {
        case '取消':
          await tester.tap(_dialogAction('取消'));
        case '遮罩':
          await tester.tapAt(const Offset(5, 5));
        case '系统返回':
          await tester.binding.handlePopRoute();
        case '空白保存':
          await tester.tap(_dialogAction('保存'));
      }
      await _finishExit(tester);
      expect(notes.items, isEmpty);
      expect(find.byType(SelectionLayer), findsOneWidget);
      await _openEditor(tester);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      await tester.tap(_dialogAction('取消'));
      await _finishExit(tester);
      expect(notes.items, isEmpty);
    });
  }
}
