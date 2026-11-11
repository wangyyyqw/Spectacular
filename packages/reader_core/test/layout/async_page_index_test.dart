import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

PageBlock _block(int id, int count, {double lineHeight = 20}) => PageBlock(
  layout: TextLayoutResult(
    text: '甲' * count,
    width: 96,
    height: count * lineHeight,
    maxWidth: 96,
    lines: [
      for (var line = 0; line < count; line++)
        LineBox(
          start: line,
          end: line + 1,
          top: line * lineHeight,
          height: lineHeight,
          baseline: line * lineHeight + lineHeight * 0.75,
          width: 96,
        ),
    ],
  ),
  style: ComputedStyle({'font-size': '16px', 'margin': '0'}),
  startCfi: 'epubcfi(/6/2!/4/2[b$id])',
  endCfi: 'epubcfi(/6/2!/4/2[b$id]:$count)',
);

ChapterPagination _paginate(List<PageBlock> blocks, {double height = 80}) =>
    Paginator(
      pageWidth: 96,
      pageHeight: height,
    ).measureChapter(blocks: blocks, spineIndex: 3);

Uint8List _hex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

Object _geometry(List<PageContent> pages) => [
  for (final page in pages)
    [
      page.spineIndex,
      page.pageIndex,
      page.usedHeight,
      page.pageHeight,
      page.topPadding,
      [
        for (final slice in page.slices)
          [
            slice.startLine,
            slice.endLine,
            slice.height,
            slice.leadingExtent,
            slice.trailingExtent,
            slice.leftInset,
            slice.textTopTrim,
            slice.textBottomTrim,
            slice.overlay,
            slice.absoluteTop,
            slice.block.startCfi,
            slice.block.endCfi,
            slice.block.spaceBefore,
            slice.block.spaceAfter,
            slice.block.layout.text,
            [
              for (final line in slice.lines)
                [
                  line.start,
                  line.end,
                  line.top,
                  line.height,
                  line.baseline,
                  line.width,
                ],
            ],
          ],
      ],
    ],
];

class _Cancelled implements Exception {
  const _Cancelled();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同步与异步编码保留 v9 固定字节，解码条目一致并拒绝旧 v8', () async {
    const index = PageIndex(
      schemaVersion: 9,
      entries: [
        PageIndexEntry(
          blockIndex: 3,
          startLine: 7,
          usedHeight: 42.5,
          pageHeight: 100,
          topPadding: -5,
        ),
      ],
    );
    final persisted = _hex(
      '52504931000900000001'
      '000000030000000740454000000000004059000000000000c014000000000000'
      '0000023c',
    );
    expect(PageIndex.currentSchemaVersion, 9);
    expect(index.encode(), persisted);
    expect(await index.encodeAsync(), persisted);
    expect(PageIndex.decode(persisted)!.entries, index.entries);
    expect((await PageIndex.decodeAsync(persisted))!.entries, index.entries);
    final old = Uint8List.fromList(persisted)..[5] = 8;
    expect(PageIndex.decode(old), isNull);
    expect(await PageIndex.decodeAsync(old), isNull);
  });

  test('块映射与页提取异步遍历保留原有身份、空页及重复块语义', () async {
    final block = _block(0, 6);
    final blocks = [block, _block(1, 2), block];
    final measured = _paginate(blocks);
    final pagination = ChapterPagination(
      spineIndex: 3,
      pages: [
        ...measured.pages,
        PageContent(
          spineIndex: 3,
          pageIndex: 9,
          slices: const [],
          usedHeight: 0,
          pageHeight: 80,
          topPadding: -4,
        ),
      ],
      pageHeight: 80,
      totalHeight: measured.totalHeight,
    );
    final expected = PageIndex.from(pagination, blocks);
    final actual = await PageIndex.fromAsync(pagination, blocks);
    expect(actual.entries, expected.entries);
    expect(await actual.encodeAsync(), expected.encode());
  });

  for (final trim in [false, true]) {
    test('异步回放与同步回放的行、边距、容器内缩和 CFI 严格相等：trim=$trim', () async {
      final container = PageContainer(
        style: ComputedStyle({'padding': '2px', 'border': '1px solid #000'}),
        left: 3,
        width: 90,
      );
      final raw = [
        _block(0, 3).withSpacing(
          spaceAfter: 8,
          containers: [
            PageContainerFragment(
              container: container,
              startsHere: true,
              endsHere: true,
              topInset: 3,
              bottomInset: 3,
            ),
          ],
        ),
        _block(1, 7).withSpacing(spaceBefore: 5, spaceAfter: 7),
        _block(2, 2).withSpacing(spaceBefore: -2),
      ];
      final blocks = PageBlock.collapseAdjacentMargins(raw);
      final pagination = Paginator(
        pageWidth: 96,
        pageHeight: 90,
        trimTextEdges: trim,
      ).measureChapter(blocks: blocks, spineIndex: 3);
      final index = PageIndex.from(pagination, blocks);
      final expected = PageIndex.apply(
        index,
        raw,
        spineIndex: 3,
        trimTextEdges: trim,
      );
      final actual = await PageIndex.applyAsync(
        index,
        raw,
        spineIndex: 3,
        trimTextEdges: trim,
      );
      expect(expected, isNotNull);
      expect(_geometry(actual!), _geometry(expected!));
      expect(() => actual.first.slices.clear(), throwsUnsupportedError);
    });
  }

  test('异步解码保留魔数、版本、长度和校验和容错', () async {
    final blocks = [_block(0, 8)];
    final bytes = PageIndex.from(_paginate(blocks), blocks).encode();
    final malformed = [
      Uint8List.fromList(bytes)..[0] = 0,
      Uint8List.fromList(bytes)..[5] = 5,
      Uint8List.sublistView(bytes, 0, bytes.length - 1),
      Uint8List.fromList(bytes)..[bytes.length - 1] ^= 0xFF,
      Uint8List(0),
    ];
    for (final value in malformed) {
      expect(await PageIndex.decodeAsync(value), PageIndex.decode(value));
      expect(await PageIndex.decodeAsync(value), isNull);
    }
  });

  test('异步回放保留空索引、越界及失效几何回退', () async {
    final blocks = [_block(0, 4), _block(1, 2)];
    const cases = [
      PageIndex(schemaVersion: 5, entries: []),
      PageIndex(schemaVersion: 6, entries: []),
      PageIndex(schemaVersion: PageIndex.currentSchemaVersion, entries: []),
      PageIndex(
        schemaVersion: PageIndex.currentSchemaVersion,
        entries: [
          PageIndexEntry(
            blockIndex: 9,
            startLine: 0,
            usedHeight: 20,
            pageHeight: 80,
            topPadding: 0,
          ),
        ],
      ),
      PageIndex(
        schemaVersion: PageIndex.currentSchemaVersion,
        entries: [
          PageIndexEntry(
            blockIndex: 0,
            startLine: 99,
            usedHeight: 20,
            pageHeight: 80,
            topPadding: 0,
          ),
        ],
      ),
      PageIndex(
        schemaVersion: PageIndex.currentSchemaVersion,
        entries: [
          PageIndexEntry(
            blockIndex: 0,
            startLine: 0,
            usedHeight: 999,
            pageHeight: 80,
            topPadding: 0,
          ),
        ],
      ),
    ];
    for (final index in cases) {
      expect(await PageIndex.applyAsync(index, blocks, spineIndex: 3), isNull);
      expect(PageIndex.apply(index, blocks, spineIndex: 3), isNull);
    }
  });

  test('提取、编解码、边距折叠及单片长行遍历中取消均不提交结果', () async {
    final manyBlocks = List.generate(4096, (i) => _block(i, 1, lineHeight: 1));
    final chapter = _paginate(manyBlocks, height: 100);
    final tall = [_block(0, 4096, lineHeight: 1)];
    final manyPages = _paginate(tall, height: 1);
    final onePage = PageIndex.from(_paginate(tall, height: 5000), tall);
    final index = PageIndex.from(manyPages, tall);
    final bytes = index.encode();
    final originalBytes = Uint8List.fromList(bytes);
    final originalBlocks = List<PageBlock>.of(manyBlocks);
    final operations =
        <String, Future<Object?> Function(Future<void> Function())>{
          '块身份映射': (checkpoint) =>
              PageIndex.fromAsync(chapter, manyBlocks, checkpoint: checkpoint),
          '页条目提取': (checkpoint) =>
              PageIndex.fromAsync(manyPages, tall, checkpoint: checkpoint),
          '编码': (checkpoint) => index.encodeAsync(checkpoint: checkpoint),
          '解码': (checkpoint) =>
              PageIndex.decodeAsync(bytes, checkpoint: checkpoint),
          '边距折叠': (checkpoint) => PageIndex.applyAsync(
            PageIndex.from(chapter, manyBlocks),
            manyBlocks,
            spineIndex: 3,
            checkpoint: checkpoint,
          ),
          '单片长行': (checkpoint) => PageIndex.applyAsync(
            onePage,
            tall,
            spineIndex: 3,
            checkpoint: checkpoint,
          ),
        };
    for (final operation in operations.entries) {
      var calls = 0;
      var committed = false;
      final result = operation
          .value(() async {
            if (++calls == 20) throw const _Cancelled();
          })
          .then((value) {
            committed = true;
            return value;
          });
      await expectLater(
        result,
        throwsA(isA<_Cancelled>()),
        reason: operation.key,
      );
      expect(committed, isFalse, reason: operation.key);
      expect(bytes, originalBytes);
      expect(manyBlocks, originalBlocks);
    }
  });
}
