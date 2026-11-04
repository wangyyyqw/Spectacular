import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/panels/annotation_panel.dart';

ReaderAnnotation _annotation({
  required String id,
  required ReaderAnnotationType type,
  required String quote,
  String? note,
  int minute = 0,
  String startCfi = 'epubcfi(/6/2!/4/2/1:0)',
}) {
  final time = DateTime(2026, 11, 3, 10, minute);
  return ReaderAnnotation(
    id: id,
    type: type,
    startCfi: startCfi,
    endCfi: 'epubcfi(/6/2!/4/2/1:4)',
    quote: quote,
    color: type == ReaderAnnotationType.highlight ? 0xFFFFEB3B : null,
    note: note,
    createdAt: time,
    updatedAt: time,
  );
}

void main() {
  testWidgets('标注面板：按类型筛选、点击跳转和编辑', (tester) async {
    final selected = <ReaderAnnotation>[];
    final edited = <ReaderAnnotation>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'note-old',
                type: ReaderAnnotationType.note,
                quote: '较早的笔记原文',
                note: '较早的笔记内容',
                minute: 1,
              ),
              _annotation(
                id: 'highlight',
                type: ReaderAnnotationType.highlight,
                quote: '一段高亮原文',
                minute: 2,
              ),
              _annotation(
                id: 'note-new',
                type: ReaderAnnotationType.note,
                quote: '最新的笔记原文',
                note: '最新的笔记内容',
                minute: 3,
              ),
            ],
            onSelect: selected.add,
            onEdit: edited.add,
          ),
        ),
      ),
    );

    expect(find.text('笔记与高亮'), findsOneWidget);
    expect(find.text('共 3 条'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('最新的笔记原文')).dy,
      lessThan(tester.getTopLeft(find.text('一段高亮原文')).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-filter-notes')),
    );
    await tester.pump();
    expect(find.text('最新的笔记原文'), findsOneWidget);
    expect(find.text('较早的笔记原文'), findsOneWidget);
    expect(find.text('一段高亮原文'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-row-note-new')),
    );
    expect(selected.single.id, 'note-new');

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-edit-note-old')),
    );
    expect(edited.single.id, 'note-old');
  });

  testWidgets('标注面板：全部与空态文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: const <ReaderAnnotation>[],
            onSelect: (_) {},
            onEdit: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('还没有笔记或高亮'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-filter-notes')),
    );
    await tester.pump();
    expect(find.text('还没有笔记'), findsOneWidget);
  });

  testWidgets('标注面板：搜索原文和笔记正文并清除', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'highlight-search',
                type: ReaderAnnotationType.highlight,
                quote: '落霞与孤鹜齐飞',
                minute: 1,
              ),
              _annotation(
                id: 'note-search',
                type: ReaderAnnotationType.note,
                quote: '春风又绿江南岸',
                note: '这里想到故乡',
                minute: 2,
              ),
            ],
            onSelect: (_) {},
            onEdit: (_) {},
          ),
        ),
      ),
    );

    final search = find.byKey(
      const ValueKey<String>('annotation-search-input'),
    );
    await tester.enterText(search, '故乡');
    await tester.pump();
    expect(find.text('春风又绿江南岸'), findsOneWidget);
    expect(find.text('落霞与孤鹜齐飞'), findsNothing);
    expect(find.text('显示 1 / 2 条'), findsOneWidget);

    await tester.enterText(search, '孤鹜');
    await tester.pump();
    expect(find.text('落霞与孤鹜齐飞'), findsOneWidget);
    expect(find.text('春风又绿江南岸'), findsNothing);

    await tester.enterText(search, '不存在');
    await tester.pump();
    expect(find.text('没有匹配的笔记或高亮'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-search-clear')),
    );
    await tester.pump();
    expect(find.text('共 2 条'), findsOneWidget);
    expect(find.text('落霞与孤鹜齐飞'), findsOneWidget);
    expect(find.text('春风又绿江南岸'), findsOneWidget);
  });

  testWidgets('标注面板：可切换最近更新与阅读顺序', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'position-first',
                type: ReaderAnnotationType.highlight,
                quote: '书中靠前的内容',
                minute: 1,
                startCfi: 'epubcfi(/6/2!/4/2/1:0)',
              ),
              _annotation(
                id: 'position-later',
                type: ReaderAnnotationType.highlight,
                quote: '书中靠后的内容',
                minute: 2,
                startCfi: 'epubcfi(/6/4!/4/2/1:0)',
              ),
            ],
            onSelect: (_) {},
            onEdit: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('书中靠后的内容')).dy,
      lessThan(tester.getTopLeft(find.text('书中靠前的内容')).dy),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-sort')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('annotation-sort-position'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('书中靠前的内容')).dy,
      lessThan(tester.getTopLeft(find.text('书中靠后的内容')).dy),
    );
  });

  testWidgets('标注面板：展示章节并支持按章节搜索', (tester) async {
    String? chapterTitleOf(ReaderAnnotation annotation) {
      if (annotation.id == 'chapter-note') {
        return '第三章 春风';
      }
      return '第一章 落霞';
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'chapter-note',
                type: ReaderAnnotationType.note,
                quote: '江南岸的原文',
                note: '这里的笔记',
                minute: 1,
              ),
              _annotation(
                id: 'chapter-highlight',
                type: ReaderAnnotationType.highlight,
                quote: '孤鹜齐飞的原文',
                minute: 2,
              ),
            ],
            chapterTitleOf: chapterTitleOf,
            onSelect: (_) {},
            onEdit: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('annotation-chapter-chapter-note')),
      findsOneWidget,
    );
    expect(find.text('第三章 春风'), findsOneWidget);
    expect(find.text('第一章 落霞'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('annotation-search-input')),
      '第三章',
    );
    await tester.pump();
    expect(find.text('江南岸的原文'), findsOneWidget);
    expect(find.text('孤鹜齐飞的原文'), findsNothing);
  });

  testWidgets('标注面板：批量选择并确认删除', (tester) async {
    final selected = <ReaderAnnotation>[];
    final deleted = <List<ReaderAnnotation>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'note-batch',
                type: ReaderAnnotationType.note,
                quote: '需要保留到筛选后的笔记',
                note: '批量删除测试',
                minute: 1,
              ),
              _annotation(
                id: 'highlight-batch',
                type: ReaderAnnotationType.highlight,
                quote: '需要批量选择的高亮',
                minute: 2,
              ),
            ],
            onSelect: selected.add,
            onEdit: (_) {},
            onDelete: (items) async => deleted.add(items),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-manage')),
    );
    await tester.pump();
    expect(find.text('已选 0 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-row-highlight-batch')),
    );
    await tester.pump();
    expect(selected, isEmpty);
    expect(find.text('已选 1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-select-all')),
    );
    await tester.pump();
    expect(find.text('已选 2 条'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-select-all')),
    );
    await tester.pump();
    expect(find.text('已选 0 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-filter-notes')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-select-all')),
    );
    await tester.pump();
    expect(find.text('已选 1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-delete')),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除 1 条标注？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-confirm-cancel')),
    );
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('已选 1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-confirm-delete')),
    );
    await tester.pumpAndSettle();

    expect(deleted.single.single.id, 'note-batch');
    expect(find.text('笔记与高亮'), findsOneWidget);
  });

  testWidgets('标注面板：窄屏批量更换标注颜色', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final recolored = <(List<ReaderAnnotation>, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'highlight-recolor',
                type: ReaderAnnotationType.highlight,
                quote: '需要更换颜色的高亮',
                minute: 1,
              ),
              _annotation(
                id: 'note-recolor',
                type: ReaderAnnotationType.note,
                quote: '需要更换颜色的笔记',
                note: '批量更改颜色',
                minute: 2,
              ),
            ],
            onSelect: (_) {},
            onEdit: (_) {},
            onDelete: (_) async {},
            onRecolor: (items, color) async =>
                recolored.add((List.of(items), color)),
          ),
        ),
      ),
    );

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

    expect(find.text('更换 2 条标注的颜色'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('annotation-batch-color-0xFF90CAF9'),
      ),
    );
    await tester.pumpAndSettle();

    expect(recolored, hasLength(1));
    expect(recolored.single.$1, hasLength(2));
    expect(recolored.single.$2, 0xFF90CAF9);
    expect(find.text('已选 2 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标注面板：墨水屏统一标记色并隐藏批量换色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'highlight-ink',
                type: ReaderAnnotationType.highlight,
                quote: '墨水屏下应显示黑色标记',
              ),
            ],
            inkMode: true,
            onSelect: (_) {},
            onEdit: (_) {},
            onDelete: (_) async {},
            onRecolor: (_, _) async {},
          ),
        ),
      ),
    );

    final bar = tester.widget<ColoredBox>(
      find.byKey(
        const ValueKey<String>('annotation-color-bar-highlight-ink'),
      ),
    );
    expect(bar.color, const Color(0xFF000000));

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-manage')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('annotation-batch-recolor')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-batch-delete')),
      findsOneWidget,
    );
  });

  testWidgets('标注面板：长笔记可原位展开和收起', (tester) async {
    final selected = <ReaderAnnotation>[];
    final longNote = List<String>.filled(18, '这段笔记需要完整阅读').join('，');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'long-note',
                type: ReaderAnnotationType.note,
                quote: '需要解释的原文',
                note: longNote,
              ),
            ],
            onSelect: selected.add,
            onEdit: (_) {},
          ),
        ),
      ),
    );

    Text noteText() => tester.widget<Text>(
      find.byKey(const ValueKey<String>('annotation-note-long-note')),
    );

    final collapsedHeight = tester.getSize(
      find.byKey(const ValueKey<String>('annotation-note-long-note')),
    ).height;
    expect(noteText().maxLines, 3);
    expect(find.text('展开笔记'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-expand-long-note')),
    );
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    expect(noteText().maxLines, isNull);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('annotation-note-long-note')),
          )
          .height,
      greaterThan(collapsedHeight),
    );
    expect(find.text('收起笔记'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-expand-long-note')),
    );
    await tester.pumpAndSettle();

    expect(noteText().maxLines, 3);
    expect(find.text('展开笔记'), findsOneWidget);
  });

  testWidgets('标注面板：筛选和搜索变化时清空已选', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [
              _annotation(
                id: 'note-reset',
                type: ReaderAnnotationType.note,
                quote: '筛选变化',
                minute: 1,
              ),
              _annotation(
                id: 'highlight-reset',
                type: ReaderAnnotationType.highlight,
                quote: '搜索变化',
                minute: 2,
              ),
            ],
            onSelect: (_) {},
            onEdit: (_) {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-batch-manage')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-row-highlight-reset')),
    );
    await tester.pump();
    expect(find.text('已选 1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-filter-notes')),
    );
    await tester.pump();
    expect(find.text('已选 0 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-row-note-reset')),
    );
    await tester.pump();
    expect(find.text('已选 1 条'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('annotation-search-input')),
      '不存在',
    );
    await tester.pump();
    expect(find.text('已选 0 条'), findsOneWidget);
  });
}
