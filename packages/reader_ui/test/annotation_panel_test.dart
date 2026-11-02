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
}
