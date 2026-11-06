import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/decorations.dart';
import 'package:reader_ui/annotations/relocator.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/selection/selection.dart';

import '../support/test_epub.dart';

Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

String _textOfLines(List<AnnotationLine> lines) => lines
    .map((line) => line.line.text.substring(line.startOffset, line.endOffset))
    .join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('改字号重排后标注覆盖文字不变（P4-20 验收）', () async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'reflow-annotation',
    );
    await session.open();
    final page = session.page!;

    // 取第二行中间的一段文字做标注。
    final boxes = TextHitTester.lineBoxes(page);
    final target = boxes[1];
    final startHit = TextHitTester.hitTest(
      page,
      Offset(target.rect.left + target.rect.width * 0.2, target.rect.center.dy),
    )!;
    final endHit = TextHitTester.hitTest(
      page,
      Offset(target.rect.left + target.rect.width * 0.6, target.rect.center.dy),
    )!;
    final selection = ReaderSelection.normalized(startHit, endHit);
    final cfi = SelectionOps.cfiOf(selection)!;
    final quote = SelectionOps.textOf(page, selection);
    expect(quote.trim(), isNotEmpty);

    final annotation = ReaderAnnotation(
      id: 'reflow',
      type: ReaderAnnotationType.mark,
      startCfi: cfi.start,
      endCfi: cfi.end,
      quote: quote,
      color: 0xFFFFEB3B,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // 重排前：标注命中当前排版并覆盖原文。
    final pagesBefore = await session.chapterPages();
    final before = AnnotationRelocator.relocate(
      annotations: <ReaderAnnotation>[annotation],
      pages: pagesBefore,
    ).single;
    expect(before.status, AnnotationRelocationStatus.verified);
    expect(
      _textOfLines(
        AnnotationDecorations.linesFor(page, <ReaderAnnotation>[
          before.resolved,
        ]),
      ),
      quote,
    );

    // 改字号：块 CFI 不变，标注应仍 verified 且覆盖同一段文字。
    await session.applyOverrides(const ReaderOverrides(fontSize: 22));
    final pagesAfter = await session.chapterPages();
    final after = AnnotationRelocator.relocate(
      annotations: <ReaderAnnotation>[annotation],
      pages: pagesAfter,
    ).single;
    expect(after.status, AnnotationRelocationStatus.verified);
    expect(after.startCfi, annotation.startCfi, reason: 'CFI 不随字号变化');

    // 在重排后的每一页上找覆盖片段，文字必须与原标注一致。
    var found = false;
    for (final candidate in pagesAfter) {
      final lines = AnnotationDecorations.linesFor(
        candidate,
        <ReaderAnnotation>[after.resolved],
      );
      if (lines.isEmpty) {
        continue;
      }
      expect(_textOfLines(lines), quote, reason: '重排后覆盖文字不变');
      found = true;
    }
    expect(found, isTrue, reason: '重排后标注仍能落到页面上，不丢');
    session.dispose();
  });

  test('标注数据在重排后不丢：失效时保留引文与前后文', () async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'reflow-keep',
    );
    await session.open();
    final page = session.page!;
    final boxes = TextHitTester.lineBoxes(page);
    final hit = TextHitTester.hitTest(
      page,
      Offset(boxes.first.rect.left + 5, boxes.first.rect.center.dy),
    )!;
    final selection = ReaderSelection.normalized(
      hit,
      hit.lineBox.text.isEmpty
          ? hit
          : SelectionOps.charAt(
              page,
              Offset(boxes.first.rect.left + 30, boxes.first.rect.center.dy),
            ),
    );
    final cfi = SelectionOps.cfiOf(selection);
    if (cfi == null) {
      session.dispose();
      return;
    }
    final annotation = ReaderAnnotation(
      id: 'keep',
      type: ReaderAnnotationType.mark,
      startCfi: cfi.start,
      endCfi: cfi.end,
      quote: SelectionOps.textOf(page, selection),
      contextBefore: '前文',
      contextAfter: '后文',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    // 用一个不存在的块 CFI 模拟失效。
    final broken = ReaderAnnotation(
      id: 'broken',
      type: annotation.type,
      startCfi: 'epubcfi(/6/999!/4/2/1:0)',
      endCfi: 'epubcfi(/6/999!/4/2/1:3)',
      quote: '书中不存在的内容',
      contextBefore: '前文',
      contextAfter: '后文',
      createdAt: annotation.createdAt,
      updatedAt: annotation.updatedAt,
    );
    await session.applyOverrides(const ReaderOverrides(fontSize: 24));
    final pages = await session.chapterPages();
    final results = AnnotationRelocator.relocate(
      annotations: <ReaderAnnotation>[broken],
      pages: pages,
    );
    expect(results.single.status, AnnotationRelocationStatus.failed);
    expect(results.single.isResolved, isFalse);
    expect(results.single.annotation.quote, '书中不存在的内容', reason: '数据保留');
    expect(results.single.annotation.contextBefore, '前文');
    session.dispose();
  });
}
