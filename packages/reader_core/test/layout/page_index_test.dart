import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// P7-22：页索引持久化——编解码容错 + 按边界重放与重排结果一致。
void main() {
  final style = ComputedStyle(const <String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': 'Ahem',
  });

  List<PageBlock> blocksOf(List<String> texts) => <PageBlock>[
    for (final text in texts)
      PageBlock.styled(
        layout: TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: 128,
        ),
        style: style,
        containingWidth: 128,
      ),
  ];

  ChapterPagination paginate(List<PageBlock> blocks, {double pageHeight = 72}) =>
      Paginator(pageHeight: pageHeight).measureChapter(blocks: blocks);

  test('编解码 roundtrip：条目逐字段一致', () {
    final blocks = blocksOf(<String>['第一段内容比较长会跨页切分', '第二段', '第三段']);
    final pagination = paginate(blocks);
    final index = PageIndex.from(pagination, blocks);
    final decoded = PageIndex.decode(index.encode());
    expect(decoded, isNotNull);
    expect(decoded!.schemaVersion, PageIndex.currentSchemaVersion);
    expect(decoded.entries, index.entries);
  });

  test('V1 以外的页索引不参与解码或重放，不影响书签位置', () {
    final blocks = blocksOf(['正文旧页边界不能重用。']);
    final index = PageIndex.from(paginate(blocks), blocks);
    expect(PageIndex.currentSchemaVersion, 1);
    for (final version in [0, 2, 4, 5, 6, 7, 8, 9, 10, 11]) {
      final old = PageIndex(schemaVersion: version, entries: index.entries);
      expect(PageIndex.decode(old.encode()), isNull);
      expect(PageIndex.apply(old, blocks, spineIndex: 0), isNull);
    }
  });

  test('重放：apply 结果与重排逐页一致（切片行区间与几何）', () {
    final blocks = blocksOf(<String>['第一段内容比较长会跨页切分', '第二段', '第三段']);
    final pagination = paginate(blocks);
    final index = PageIndex.from(pagination, blocks);
    final replayed = PageIndex.apply(index, blocks, spineIndex: 0)!;
    expect(replayed, hasLength(pagination.pages.length));
    for (var i = 0; i < replayed.length; i++) {
      expect(replayed[i].pageIndex, pagination.pages[i].pageIndex);
      expect(replayed[i].usedHeight, closeTo(pagination.pages[i].usedHeight, 0.01));
      expect(replayed[i].topPadding, pagination.pages[i].topPadding);
      expect(replayed[i].slices, hasLength(pagination.pages[i].slices.length));
      for (var s = 0; s < replayed[i].slices.length; s++) {
        expect(replayed[i].slices[s].startLine, pagination.pages[i].slices[s].startLine);
        expect(replayed[i].slices[s].endLine, pagination.pages[i].slices[s].endLine);
      }
    }
  });

  test('容错：魔数错 / schema 不匹配 / 截断 / 校验和错 → null', () {
    final blocks = blocksOf(<String>['第一段内容比较长会跨页切分', '第二段']);
    final index = PageIndex.from(paginate(blocks), blocks);
    final bytes = index.encode();

    // 魔数错。
    final badMagic = Uint8List.fromList(bytes)..[0] = 0x00;
    expect(PageIndex.decode(badMagic), isNull);

    // schema 不匹配。
    final badSchema = Uint8List.fromList(bytes)..[5] = 0x63;
    expect(PageIndex.decode(badSchema), isNull);

    // 截断。
    expect(PageIndex.decode(Uint8List.sublistView(bytes, 0, bytes.length - 8)),
        isNull);

    // 校验和错。
    final badChecksum = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 0xFF;
    expect(PageIndex.decode(badChecksum), isNull);
  });

  test('重放容错：边界越界 / 空切片 → null 回退重排', () {
    // 首块足够长 + 页高只容一块，保证索引引用到块 1（跨块分页）。
    final blocks = blocksOf(<String>['第一段内容比较长会跨页切分', '第二段']);
    final good = PageIndex.from(paginate(blocks, pageHeight: 48), blocks);
    expect(good.entries.length, greaterThanOrEqualTo(2));
    expect(
      PageIndex.apply(
        PageIndex(
          schemaVersion: PageIndex.currentSchemaVersion,
          entries: <PageIndexEntry>[
            const PageIndexEntry(
              blockIndex: 9,
              startLine: 0,
              usedHeight: 24,
              pageHeight: 72,
              topPadding: 0,
            ),
          ],
        ),
        blocks,
        spineIndex: 0,
      ),
      isNull,
    );
    expect(
      PageIndex.apply(
        PageIndex(schemaVersion: PageIndex.currentSchemaVersion, entries: good.entries),
        blocksOf(<String>['只有一段']), // 块数不足。
        spineIndex: 0,
      ),
      isNull,
    );
    expect(
      PageIndex.apply(
        const PageIndex(schemaVersion: PageIndex.currentSchemaVersion, entries: <PageIndexEntry>[]),
        blocks,
        spineIndex: 0,
      ),
      isNull,
    );
  });
}
