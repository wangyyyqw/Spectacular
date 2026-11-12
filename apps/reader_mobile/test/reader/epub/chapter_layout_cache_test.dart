import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';

CompletedChapterLayout _entry(String key, {int indexBytes = 0}) {
  final block = PageBlock(
    layout: TextLayoutResult(
      text: '缓存原文',
      lines: const [],
      width: 320,
      height: 0,
      maxWidth: 320,
      runs: const [],
    ),
  );
  return CompletedChapterLayout(
    key: key,
    spineIndex: 0,
    pages: [
      PageContent(
        spineIndex: 0,
        pageIndex: 0,
        slices: [
          PageBlockSlice(block: block, startLine: 0, endLine: 0, height: 0),
        ],
        usedHeight: 0,
        pageHeight: 480,
        topPadding: 0,
      ),
    ],
    blocks: [block],
    fixedBlocks: const [],
    background: null,
    fontDependency: '字体',
    pageIndex: Uint8List(indexBytes),
  );
}

void main() {
  test('三项上限优先保留当前章与上一字号，剩余项按访问顺序淘汰', () {
    final cache = ChapterLayoutCache();
    cache.setCurrent('字号21');
    cache.put(_entry('字号21'));
    cache.setCurrent('字号22');
    cache.put(_entry('字号22'));
    cache.put(_entry('邻章'));
    cache.get('字号21', '字体');
    cache.put(_entry('新邻章'));
    expect(cache.length, ChapterLayoutCache.maxEntries);
    expect(cache.get('邻章', '字体'), isNull);
    expect(cache.get('字号21', '字体'), isNotNull);
    expect(cache.get('字号22', '字体'), isNotNull);
    expect(
      cache.estimatedBytes,
      lessThanOrEqualTo(ChapterLayoutCache.maxBytes),
    );
  });

  test('容量包含索引字节，必要时淘汰上一字号但始终保留当前结果', () {
    final cache = ChapterLayoutCache();
    const size = ChapterLayoutCache.maxBytes ~/ 2;
    cache.setCurrent('旧');
    cache.put(_entry('旧', indexBytes: size));
    cache.setCurrent('新');
    final latest = _entry('新', indexBytes: size);
    expect(cache.put(latest), isTrue);
    expect(cache.get('旧', '字体'), isNull);
    expect(cache.get('新', '字体'), same(latest));
    expect(cache.estimatedBytes, latest.estimatedBytes);
    expect(
      cache.estimatedBytes,
      lessThanOrEqualTo(ChapterLayoutCache.maxBytes),
    );
  });

  test('64MiB 边界布局可缓存，多一个字节时拒绝且保留已有条目', () {
    final cache = ChapterLayoutCache();
    expect(ChapterLayoutCache.maxBytes, 64 * 1024 * 1024);
    final layoutBytes = _entry('边界').estimatedBytes;
    final indexBytes = ChapterLayoutCache.maxBytes - layoutBytes;
    final boundary = _entry('边界', indexBytes: indexBytes);
    cache.setCurrent(boundary.key);
    expect(boundary.estimatedBytes, ChapterLayoutCache.maxBytes);
    expect(cache.put(boundary), isTrue);

    final oversized = _entry('超预算', indexBytes: indexBytes + 1);
    expect(oversized.estimatedBytes, ChapterLayoutCache.maxBytes + 1);
    expect(cache.put(oversized), isFalse);
    expect(cache.length, 1);
    expect(cache.estimatedBytes, ChapterLayoutCache.maxBytes);
    expect(cache.get(boundary.key, '字体'), same(boundary));
  });

  test('行内文字、表格格内载荷和脚注正文超过容量时拒绝缓存', () {
    final text = '甲' * (ChapterLayoutCache.maxBytes ~/ 2 + 1);
    final inline = _inlineBlock([_textBlock(text)]);
    final examples = {
      '行内载荷': inline,
      '表格内盒': _tableBlock(inline.layout),
      '脚注正文': _textBlock('正文', notes: [_note(text)]),
    };
    for (final example in examples.entries) {
      final cache = ChapterLayoutCache();
      final entry = _fromBlock(example.value);
      expect(
        entry.estimatedBytes,
        greaterThan(ChapterLayoutCache.maxBytes),
        reason: example.key,
      );
      expect(cache.put(entry), isFalse, reason: example.key);
      expect(cache.length, 0);
      debugPrint('缓存容量：${example.key} = ${entry.estimatedBytes} 字节');
    }
  });

  test('共享行内图片字节只计一次，视图持有的完整缓冲区计入容量', () {
    final data = Uint8List(12 * 1024 * 1024);
    final payload = _inlineBlock([data]);
    final shared = _fromBlock(_inlineBlock([payload, payload, payload]));
    final cache = ChapterLayoutCache();
    expect(shared.estimatedBytes, greaterThan(data.lengthInBytes));
    expect(shared.estimatedBytes, lessThan(ChapterLayoutCache.maxBytes));
    expect(cache.put(shared), isTrue);

    final backing = Uint8List(ChapterLayoutCache.maxBytes + 1);
    final view = Uint8List.view(backing.buffer, 0, 1);
    final oversized = _fromBlock(_inlineBlock([view]));
    expect(oversized.estimatedBytes, greaterThan(ChapterLayoutCache.maxBytes));
    expect(cache.put(oversized), isFalse);
    expect(cache.length, 1);
    debugPrint(
      '缓存容量：共享图片 = ${shared.estimatedBytes} 字节，'
      '完整缓冲区视图 = ${oversized.estimatedBytes} 字节',
    );
  });

  test('图片路径与共享脚注字符串参与估算，字符串共享时不重复累计', () {
    final text = '图片说明' * 2000;
    final note = _note(text, images: [text]);
    final shared = _fromBlock(_textBlock(text, notes: [note, note]));
    final plain = _fromBlock(_textBlock(text));
    expect(shared.estimatedBytes, greaterThan(plain.estimatedBytes));
    expect(shared.estimatedBytes - plain.estimatedBytes, lessThan(1024));
    final image = _fromBlock(
      _textBlock(
        '正文',
        notes: [
          _note('', images: [text]),
        ],
      ),
    );
    expect(image.estimatedBytes, greaterThan(text.length * 2));
  });

  test('大量短字符串按引用保守计费，同值不同实例不进入身份碰撞链', () async {
    const count = 10000;
    final units = List<int>.filled(64, 65);
    final distinct = List.generate(count, (_) => String.fromCharCodes(units));
    expect(identical(distinct[0], distinct[1]), isFalse);
    final shared = _fromBlock(
      _inlineBlock([List.filled(count, distinct.first)]),
    );
    final separate = _fromBlock(_inlineBlock([distinct]));

    expect(shared.estimatedBytes, separate.estimatedBytes);
    expect(separate.estimatedBytes, greaterThanOrEqualTo(count * 64 * 2));
    expect(separate.estimatedBytes, lessThan(ChapterLayoutCache.maxBytes));
    expect(ChapterLayoutCache().put(separate), isTrue);
    var checkpoints = 0;
    final asynchronous = await _asyncFrom(
      separate,
      checkpoint: () async => checkpoints += 1,
    );
    expect(asynchronous.estimatedBytes, separate.estimatedBytes);
    expect(checkpoints, greaterThanOrEqualTo(count));
  });

  test('超过短字符串阈值的正文仍按身份去重，不合并同值不同实例', () {
    const count = 200;
    final units = List<int>.filled(65, 65);
    final distinct = List.generate(count, (_) => String.fromCharCodes(units));
    final shared = _fromBlock(
      _inlineBlock([List.filled(count, distinct.first)]),
    );
    final separate = _fromBlock(_inlineBlock([distinct]));

    expect(
      separate.estimatedBytes - shared.estimatedBytes,
      (count - 1) * 65 * 2,
    );
  });

  test('异步完成产物与同步构造估算一致，保留几何对象并冻结顶层列表', () async {
    const background = PageBackground(imageUrl: 'Images/背景.png');
    final block = _tableBlock(_inlineBlock([_textBlock('盒内文字')]).layout);
    final fixed = _textBlock('固定文字');
    final pages = [_page(block, background: background)];
    final blocks = [block];
    final overlays = [fixed];
    final synchronous = _fromBlock(
      block,
      fixed: overlays,
      background: background,
    );
    final asynchronous = await CompletedChapterLayout.createAsync(
      key: synchronous.key,
      spineIndex: synchronous.spineIndex,
      pages: pages,
      blocks: blocks,
      fixedBlocks: overlays,
      background: background,
      fontDependency: synchronous.fontDependency,
    );
    expect(asynchronous.estimatedBytes, synchronous.estimatedBytes);
    expect(asynchronous.blocks.single, same(block));
    expect(asynchronous.pages.single.slices.single.block, same(block));
    expect(asynchronous.fixedBlocks.single, same(fixed));
    expect(asynchronous.background, same(background));
    pages.clear();
    blocks.clear();
    overlays.clear();
    expect(asynchronous.pages, hasLength(1));
    expect(asynchronous.blocks, hasLength(1));
    expect(asynchronous.fixedBlocks, hasLength(1));
    expect(() => asynchronous.blocks.clear(), throwsUnsupportedError);
  });

  test('同步和异步估算终止于共享或循环载荷，不重复累计同一布局', () async {
    final lines = <LineBox>[];
    final cyclic = PageBlock(layout: _layout('\uFFFC', lines));
    lines.add(_inlineLine([cyclic]));
    final expected = _fromBlock(cyclic);
    var checkpoints = 0;
    final actual = await _asyncFrom(
      expected,
      checkpoint: () async {
        checkpoints += 1;
        if (checkpoints > 100) throw StateError('循环载荷未终止');
      },
    );
    expect(actual.estimatedBytes, expected.estimatedBytes);
    expect(actual.blocks.single, same(cyclic));
    expect(actual.estimatedBytes, lessThan(4096));
  });

  test('嵌套载荷遍历中取消保留原错误，未发布或缓存部分完成产物', () async {
    var payload = _textBlock('最深文字');
    for (var depth = 0; depth < 64; depth++) {
      payload = _inlineBlock([payload]);
    }
    final source = _fromBlock(payload);
    final cache = ChapterLayoutCache();
    final cancelled = StateError('取消完成产物估算');
    var checkpoints = 0;
    final pending = _asyncFrom(
      source,
      checkpoint: () async {
        if (++checkpoints == 80) throw cancelled;
      },
    ).then(cache.put);
    await expectLater(pending, throwsA(same(cancelled)));
    expect(checkpoints, 80);
    expect(cache.length, 0);
    expect(source.blocks.single, same(payload));
  });

  test('索引回放与注入共用一个完成条目，不保留第二套页面或块', () {
    final cache = ChapterLayoutCache();
    final entry = _entry('回放');
    cache.put(entry);
    cache.markForReplay((layout) => layout.key == '回放');
    expect(cache.requiresReplay('回放'), isTrue);
    expect(cache.get('回放', '字体'), same(entry));
    cache.injectPageIndex('回放', Uint8List(64));
    final indexed = cache.get('回放', '字体')!;
    expect(cache.length, 1);
    expect(indexed.pages.single, same(entry.pages.single));
    expect(indexed.blocks.single, same(entry.blocks.single));
    expect(indexed.estimatedBytes, entry.estimatedBytes + 64);
    expect(cache.estimatedBytes, indexed.estimatedBytes);
    expect(cache.requiresReplay('回放'), isTrue);
    cache.put(indexed);
    expect(cache.requiresReplay('回放'), isFalse);
  });

  test('字体实际依赖不匹配时拒绝并删除旧条目', () {
    final cache = ChapterLayoutCache();
    cache.put(_entry('字体晚到'));
    expect(cache.get('字体晚到', '新字体'), isNull);
    expect(cache.length, 0);
    expect(cache.estimatedBytes, 0);
  });

  test('内存压力清理非当前条目，后续重复清理与清空安全', () {
    final cache = ChapterLayoutCache();
    cache.put(_entry('旧'));
    cache.setCurrent('当前');
    final current = _entry('当前');
    cache.put(current);
    cache.put(_entry('邻章'));
    cache.clearNonCurrent();
    cache.clearNonCurrent();
    expect(cache.length, 1);
    expect(cache.get('当前', '字体'), same(current));
    expect(cache.estimatedBytes, current.estimatedBytes);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.estimatedBytes, 0);
  });
}

final _style = ComputedStyle({'font-size': '16px', 'margin': '0'});

TextLayoutResult _layout(String text, List<LineBox> lines) => TextLayoutResult(
  text: text,
  lines: lines,
  width: 100,
  height: 20,
  maxWidth: 100,
);

PageBlock _textBlock(String text, {List<PageFootnote> notes = const []}) =>
    PageBlock(layout: _layout(text, const []), footnotes: notes);

PageFootnote _note(String text, {List<String> images = const []}) =>
    PageFootnote(
      start: 0,
      end: 1,
      label: '1',
      kind: NoteKind.footnote,
      text: text,
      imageUrls: images,
    );

PageBlock _inlineBlock(List<Object> payloads) =>
    PageBlock(layout: _layout('甲\uFFFC乙', [_inlineLine(payloads)]));

LineBox _inlineLine(List<Object> payloads) => LineBox(
  start: 0,
  end: 3,
  top: 0,
  height: 20,
  baseline: 16,
  width: 100,
  inlineBoxes: [
    for (final payload in payloads)
      InlineBoxPlacement(
        offset: 1,
        left: 16,
        width: 20,
        height: 20,
        ascent: 16,
        descent: 4,
        spec: InlineBoxSpec(offset: 1, width: 20, height: 20, payload: payload),
      ),
  ],
);

PageBlock _tableBlock(TextLayoutResult cell) => PageBlock(
  layout: _layout('', const []),
  table: TableRenderSpec(
    cells: [
      TableCellRender(
        row: 0,
        rect: const Rect.fromLTWH(0, 0, 100, 20),
        layout: cell,
        style: _style,
      ),
    ],
    columnXs: const [0, 100],
    rowYs: const [0, 20],
    tableWidth: 100,
  ),
);

PageContent _page(PageBlock block, {PageBackground? background}) => PageContent(
  spineIndex: 0,
  pageIndex: 0,
  slices: [
    PageBlockSlice(
      block: block,
      startLine: 0,
      endLine: block.layout.lineCount,
      height: 20,
    ),
  ],
  usedHeight: 20,
  pageHeight: 480,
  topPadding: 0,
  background: background,
);

CompletedChapterLayout _fromBlock(
  PageBlock block, {
  List<PageBlock> fixed = const [],
  PageBackground? background,
}) => CompletedChapterLayout(
  key: '布局引用',
  spineIndex: 0,
  pages: [_page(block, background: background)],
  blocks: [block],
  fixedBlocks: fixed,
  background: background,
  fontDependency: '字体',
);

Future<CompletedChapterLayout> _asyncFrom(
  CompletedChapterLayout source, {
  Future<void> Function()? checkpoint,
}) => CompletedChapterLayout.createAsync(
  key: source.key,
  spineIndex: source.spineIndex,
  pages: source.pages,
  blocks: source.blocks,
  fixedBlocks: source.fixedBlocks,
  background: source.background,
  fontDependency: source.fontDependency,
  checkpoint: checkpoint,
);
