import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/reader_session.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实页面：随机 60 个行内坐标都命中所在行（P4-14 验收）', () async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'hit-real',
    );
    await session.open();
    final page = session.page;
    expect(page, isNotNull);
    final boxes = TextHitTester.lineBoxes(page!);
    expect(boxes, isNotEmpty, reason: '真实页应有行');

    final random = Random(7);
    var checked = 0;
    for (var i = 0; i < 60; i++) {
      final box = boxes[random.nextInt(boxes.length)];
      final x = box.rect.left + box.rect.width * random.nextDouble();
      final y = box.rect.top + box.rect.height * random.nextDouble();
      final hit = TextHitTester.hitTest(page, Offset(x, y));
      expect(hit, isNotNull);
      expect(hit!.sliceIndex, box.sliceIndex, reason: '命中切片应与行一致');
      expect(hit.lineIndex, box.lineIndex, reason: '命中行应与行一致');
      expect(hit.textOffset, greaterThanOrEqualTo(box.textOffset));
      expect(
        hit.textOffset,
        lessThanOrEqualTo(box.textOffset + box.text.length),
        reason: '字符下标不越出该行',
      );
      checked += 1;
    }
    expect(checked, 60);
    session.dispose();
  });

  test('真实页面：跨块坐标不落到上一块之外', () async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'hit-blocks',
    );
    await session.open();
    final page = session.page!;
    final boxes = TextHitTester.lineBoxes(page);
    if (boxes.map((box) => box.sliceIndex).toSet().length < 2) {
      session.dispose();
      return; // 该页只有一块时跳过
    }
    final lastBox = boxes.last;
    final hit = TextHitTester.hitTest(
      page,
      Offset(lastBox.rect.left + 1, lastBox.rect.center.dy),
    )!;
    expect(hit.sliceIndex, lastBox.sliceIndex);
    expect(hit.lineIndex, lastBox.lineIndex);
    session.dispose();
  });
}
