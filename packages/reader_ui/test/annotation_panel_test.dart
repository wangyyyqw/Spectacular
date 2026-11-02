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
}) {
  final time = DateTime(2026, 11, 3, 10, minute);
  return ReaderAnnotation(
    id: id,
    type: type,
    startCfi: 'epubcfi(/6/2!/4/2/1:0)',
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
