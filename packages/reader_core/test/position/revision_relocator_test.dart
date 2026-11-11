import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/revision_relocator.dart';

String _cfi(int spine, int block) =>
    'epubcfi(/6/${(spine + 1) * 2}!/4/${(block + 1) * 2}/1)';

AnchorChapter _chapter(
  int spine,
  List<String> texts, {
  String? href,
  String? title,
  bool readable = true,
}) => AnchorChapter(
  spineIndex: spine,
  href: href ?? 'chapter-$spine.xhtml',
  title: title ?? '第 $spine 章',
  readable: readable,
  blocks: [
    for (var i = 0; i < texts.length; i++)
      AnchorBlock(cfi: _cfi(spine, i), text: texts[i]),
  ],
);

AnchorBook _book(String revision, List<List<String>> chapters) => AnchorBook(
  revision: revision,
  chapters: [
    for (var i = 0; i < chapters.length; i++) _chapter(i, chapters[i]),
  ],
);

LocationAnchor _range(AnchorBook book, int spine, String quote) {
  final chapter = book.chapter(spine)!;
  final start = chapter.text.indexOf(quote);
  expect(start, greaterThanOrEqualTo(0));
  return book.capture(
    chapter.cfiAt(start)!,
    endCfi: chapter.cfiAt(start + quote.length, end: true)!,
  )!;
}

AnchorRecord _relocate(
  AnchorBook old,
  AnchorBook current,
  LocationAnchor anchor, {
  bool progress = false,
}) => RevisionRelocator.relocate(
  oldBook: old,
  newBook: current,
  record: AnchorRecord(original: anchor),
  progress: progress,
);

bool _validUtf16(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i == text.length) return false;
      final next = text.codeUnitAt(i);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

void main() {
  const before = '甲乙丙丁戊己庚辛壬癸这是不会变化的前文用于可靠地夹定引用起点。';
  const after = '子丑寅卯辰巳午未申酉这是不会变化的后文用于可靠地夹定引用终点。';
  const quote = '旧版里需要保留的选中文字';

  test('同版本也核对实际原文；当前锚点记录真实选中文字', () {
    final book = _book('v1', [
      [before + quote + after],
    ]);
    final anchor = _range(book, 0, quote);
    final result = _relocate(book, book, anchor);
    expect(result.status, 'verified');
    expect(book.textFor(result.current!), quote);
    expect(result.original, same(anchor));
  });

  test('旧 CFI 偏移合法但新版文字不同不能直接验证', () {
    final old = _book('v1', [
      ['旧版本中的文字内容'],
    ]);
    final current = _book('v2', [
      ['另一段毫无关系内容'],
    ]);
    final result = _relocate(old, current, _range(old, 0, '旧版本'));
    expect(result.status, 'pending');
    expect(result.current, isNull);
  });

  test('前插序言、中插章节、追加后记仍跟随原文', () {
    final old = _book('v1', [
      ['第一章的独有内容'],
      [before + quote + after],
      ['最后章内容'],
    ]);
    final current = _book('v2', [
      ['新增序言'],
      ['第一章的独有内容'],
      ['新增中间章节一'],
      ['新增中间章节二'],
      [before + quote + after],
      ['最后章内容'],
      ['新增后记'],
    ]);
    final result = _relocate(old, current, _range(old, 1, quote));
    expect(result.status, 'relocated');
    expect(result.current!.start.spineIndex, 4);
    expect(current.textFor(result.current!), quote);
    expect(RevisionRelocator.hasAddedReadableContent(old, current), isTrue);
  });

  test('章节改名换路径和搬移由文本指纹关联', () {
    final old = _book('v1', [
      [before + quote + after],
      ['其他内容'],
    ]);
    final current = AnchorBook(
      revision: 'v2',
      chapters: [
        _chapter(0, ['其他内容']),
        _chapter(
          1,
          [before + quote + after],
          href: 'changed.xhtml',
          title: '新章名',
        ),
      ],
    );
    final result = _relocate(old, current, _range(old, 0, quote));
    expect(result.status, 'relocated');
    expect(result.current!.start.href, 'changed.xhtml');
    expect(current.textFor(result.current!), quote);
    expect(RevisionRelocator.hasAddedReadableContent(old, current), isFalse);
  });

  test('章节拆分时区间端点分别映射到不同章节', () {
    final old = _book('v1', [
      [before, quote, after],
    ]);
    final current = _book('v2', [
      [before],
      [quote, after],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(5)!,
      endCfi: old.chapter(0)!.cfiAt(before.length + quote.length + 4)!,
    )!;
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(result.current!.start.spineIndex, 0);
    expect(result.current!.end!.spineIndex, 1);
    expect(current.textFor(result.current!), old.textFor(anchor));
    expect(RevisionRelocator.hasAddedReadableContent(old, current), isFalse);
  });

  test('拆章前后新增章名时由不变段落定位原文，不把章名扩大进高亮', () {
    final old = _book('v1', [
      [before, quote, after],
    ]);
    final anchor = _range(old, 0, quote);
    // 排他结束点已指向后文段落，不能直接拿它的指纹验证选中文字。
    expect(anchor.end!.paragraphFingerprint, anchorFingerprint(after));
    for (final texts in [
      ['相遇下篇', quote, after],
      ['相遇下篇', quote, '新增段后标题', after],
    ]) {
      final current = AnchorBook(
        revision: 'v2',
        chapters: [
          _chapter(0, [before]),
          _chapter(1, texts, href: 'renamed.xhtml', title: '相遇下篇'),
        ],
      );
      final result = _relocate(old, current, anchor);
      expect(result.status, 'relocated');
      expect(current.textFor(result.current!), quote);
      expect(result.current!.start.spineIndex, 1);
      expect(result.current!.start.charOffset, '相遇下篇'.length);
      expect(result.current!.end!.charOffset, '相遇下篇'.length + quote.length);
    }
  });

  test('重复段落及新增章名没有可靠章节关系时仍待确认', () {
    final old = _book('v1', [
      ['短前文', quote, '短后文'],
    ]);
    final current = _book('v2', [
      ['新增标题一', quote, '另一段后文'],
      ['新增标题二', quote, '另一段结尾'],
    ]);
    final result = _relocate(old, current, _range(old, 0, quote));
    expect(result.status, 'pending');
    expect(result.current, isNull);
  });

  test('合并搬移后旧章名不再紧邻书签，由唯一不变段落保留点位置', () {
    final old = _book('v1', [
      ['旅程', before, after],
    ]);
    final anchor = old.anchorAt(0, '旅程'.length)!;
    final current = _book('v2', [
      ['新增章名', quote, before, after],
    ]);
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(result.current!.start.charOffset, '新增章名'.length + quote.length);
    expect(current.textFor(result.current!), startsWith(before));
  });

  test('合并章节及变更块分段不改变选中文字', () {
    final old = _book('v1', [
      [before + quote],
      [after],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(before.length)!,
      endCfi: old.chapter(1)!.cfiAt(12)!,
    )!;
    final current = _book('v2', [
      [before.substring(0, 8), before.substring(8) + quote + after],
    ]);
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), quote + after.substring(0, 12));
    expect(RevisionRelocator.hasAddedReadableContent(old, current), isFalse);
  });

  test('引用前插文字按原文定位而不是原偏移', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final current = _book('v2', [
      ['新增加的开场文字$before$quote$after'],
    ]);
    final result = _relocate(old, current, _range(old, 0, quote));
    expect(result.current!.start.charOffset, before.length + '新增加的开场文字'.length);
    expect(current.textFor(result.current!), quote);
  });

  test('搜索折叠空白后反向映射回块内真实偏移', () {
    final old = _book('v1', [
      [before, '表格第一格 第二格\n第三格', after],
    ]);
    final current = _book('v2', [
      ['$before表格第一格', ' \t 第二格\r\n  第三格$after'],
    ]);
    final anchor = _range(old, 0, '表格第一格 第二格\n第三格');
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '表格第一格 \t 第二格\r\n  第三格');
    expect(cfiBase(result.current!.start.cfi), _cfi(0, 0));
    expect(cfiCharOffset(result.current!.start.cfi), before.length);
    expect(cfiBase(result.current!.end!.cfi), _cfi(0, 1));
    expect(cfiCharOffset(result.current!.end!.cfi), ' \t 第二格\r\n  第三格'.length);
    expect(
      result.current!.end!.charOffset,
      before.length + '表格第一格 \t 第二格\r\n  第三格'.length,
    );
  });

  test('跨章节相邻空白也只折叠一次并保留真实范围', () {
    final old = _book('v1', [
      ['$before选择 '],
      ['文字$after'],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(before.length)!,
      endCfi: old.chapter(1)!.cfiAt(2)!,
    )!;
    final current = _book('v2', [
      ['$before选择 \n'],
      ['\t 文字$after'],
    ]);
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '选择 \n\t 文字');
  });

  test('重复原文用上下文消歧，不直接选第一条', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final current = _book('v2', [
      ['无关背景$quote无关结尾'],
      [before + quote + after],
    ]);
    final result = _relocate(old, current, _range(old, 0, quote));
    expect(result.status, 'relocated');
    expect(result.current!.start.spineIndex, 1);
    expect(current.textFor(result.current!), quote);
  });

  test('相同上下文重复且无可靠章节关系进入待确认', () {
    final text = before + quote + after;
    final old = _book('v1', [
      [text],
    ]);
    final current = _book('v2', [
      [text + text],
    ]);
    final result = _relocate(old, current, _range(old, 0, quote));
    expect(result.status, 'pending');
    expect(result.reason, contains('无法可靠消歧'));
  });

  test('引用内部完全改写由双侧唯一至少十六单元夹定', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final current = _book('v2', [
      ['$before新版作者重新写下了这一段$after'],
    ]);
    final anchor = _range(old, 0, quote);
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '新版作者重新写下了这一段');
    expect(result.original.quote, quote);
  });

  test('引用删除或双侧证据不足均不按比例挂到别处', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final removed = _book('v2', [
      [before + after],
    ]);
    expect(_relocate(old, removed, _range(old, 0, quote)).status, 'pending');
    final shortOld = _book('v1', [
      ['前文$quote后文'],
    ]);
    final changed = _book('v2', [
      ['前文另一段完全不同文字后文'],
    ]);
    expect(
      _relocate(shortOld, changed, _range(shortOld, 0, quote)).status,
      'pending',
    );
  });

  test('跨章节区间端点倒置时待确认', () {
    final first = List.filled(3, before).join();
    final last = List.filled(3, after).join();
    final old = _book('v1', [
      [first],
      ['中间段落'],
      [last],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(0)!,
      endCfi: old.chapter(2)!.cfiAt(0)!,
    )!;
    final current = _book('v2', [
      [last],
      ['中间段落'],
      [first],
    ]);
    expect(_relocate(old, current, anchor).status, 'pending');
  });

  test('修改跨章范围时短端点不能绕过双侧十六单元证据要求', () {
    for (final endpoints in [('起点', '终点'), (before, '终点'), ('起点', after)]) {
      final old = _book('v1', [
        [endpoints.$1],
        ['原范围中间的文字'],
        [endpoints.$2],
      ]);
      final current = _book('v2', [
        [endpoints.$1],
        ['中间文字完全被作者改写'],
        [endpoints.$2],
      ]);
      final anchor = old.capture(
        old.chapter(0)!.cfiAt(0)!,
        endCfi: old.chapter(2)!.cfiAt(0)!,
      )!;
      final result = _relocate(old, current, anchor);
      expect(result.status, 'pending');
      expect(result.current, isNull);
      expect(result.original, same(anchor));
    }
  });

  test('完整原文唯一且上下文吻合时短跨章端点仍可正常迁移', () {
    final old = _book('v1', [
      ['起点'],
      ['不变的中间原文'],
      ['终点'],
    ]);
    final current = _book('v2', [
      ['前插序言'],
      ['起点'],
      ['不变的中间原文'],
      ['终点'],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(0)!,
      endCfi: old.chapter(2)!.cfiAt(0)!,
    )!;
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '起点不变的中间原文');
    expect(result.current!.start.spineIndex, 1);
    // 章节边界的区间结束 CFI 使用前一章末尾，选中文字与下一章开头等价。
    expect(result.current!.end!.spineIndex, 2);
    expect(result.current!.end!.charOffset, current.chapter(2)!.text.length);
  });

  test('两端各十六个 UTF-16 单元的唯一原文足以迁移修改后的跨章范围', () {
    const first = '𠀀𠀁𠀂𠀃𠀄𠀅𠀆𠀇';
    const last = '𠮷𠮸𠮹𠮺𠮻𠮼𠮽𠮾';
    expect(first.length, 16);
    expect(last.length, 16);
    final old = _book('v1', [
      [first],
      ['原范围中间的文字'],
      [last],
    ]);
    final current = _book('v2', [
      ['新序言'],
      [first],
      ['作者修改的中间文字'],
      [last],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(0)!,
      endCfi: old.chapter(2)!.cfiAt(0)!,
    )!;
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '$first作者修改的中间文字');
    expect(result.current!.start.spineIndex, 1);
    expect(result.current!.end!.spineIndex, 2);
    expect(result.current!.end!.charOffset, current.chapter(2)!.text.length);
    expect(_validUtf16(result.current!.quote), isTrue);
  });

  test('短章末端点由十六单元唯一前文夹定后可迁移，重复前文仍待确认', () {
    const prefix = '甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳';
    final old = _book('v1', [
      [before],
      ['原范围的中间文字'],
      ['$prefix尾'],
    ]);
    final anchor = old.capture(
      old.chapter(0)!.cfiAt(0)!,
      endCfi: old.chapter(2)!.cfiAt(prefix.length)!,
    )!;
    final current = _book('v2', [
      [before],
      ['修改后的中间文字'],
      ['$prefix尾'],
    ]);
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '$before修改后的中间文字$prefix');
    final repeated = _book('v2', [
      [before],
      ['修改后的中间文字$prefix'],
      ['$prefix尾'],
    ]);
    expect(_relocate(old, repeated, anchor).status, 'pending');
  });

  test('补充平面字符窗口与修改定位不截断 UTF-16 代理对', () {
    final emojiBefore = before + List.generate(20, (i) => '$i𠀀😀').join();
    final emojiAfter = List.generate(20, (i) => '$i𠮷🪷').join() + after;
    final old = _book('v1', [
      [emojiBefore + quote + emojiAfter],
    ]);
    final anchor = _range(old, 0, quote);
    for (final point in [anchor.start, anchor.end!]) {
      expect(point.quote.length, lessThanOrEqualTo(64));
      expect(point.contextBefore.length, lessThanOrEqualTo(64));
      expect(point.contextAfter.length, lessThanOrEqualTo(64));
      expect(
        _validUtf16(point.quote + point.contextBefore + point.contextAfter),
        isTrue,
      );
    }
    final current = _book('v2', [
      ['$emojiBefore新的𠀀引文😀$emojiAfter'],
    ]);
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(current.textFor(result.current!), '新的𠀀引文😀');
    expect(_validUtf16(result.current!.quote), isTrue);
  });

  test('点锚点在移动后的章节末尾仍可恢复', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final current = _book('v2', [
      ['新增序言'],
      [before + quote + after],
    ]);
    final anchor = old.anchorAt(0, old.chapter(0)!.text.length)!;
    final result = _relocate(old, current, anchor);
    expect(result.status, 'relocated');
    expect(result.current!.start.spineIndex, 1);
    expect(result.current!.start.charOffset, current.chapter(1)!.text.length);
  });

  test('进度失败后在有独有段落关联的章节中按比例近似恢复', () {
    final old = _book('v1', [
      [before, List.filled(90, '旧').join(), after],
    ]);
    final current = _book('v2', [
      [before, List.filled(170, '新').join(), after],
    ]);
    final anchor = old.anchorAt(0, before.length + 35)!;
    final result = _relocate(old, current, anchor, progress: true);
    expect(result.status, 'approximate');
    final expected =
        (anchor.start.charOffset /
                anchor.start.chapterLength *
                current.chapter(0)!.text.length)
            .round();
    expect(result.current!.start.charOffset, expected);
    expect(result.original, same(anchor));
  });

  test('仅同名同路径不足以关联进度，优先后方已匹配章', () {
    final old = _book('v1', [
      [before],
      ['已被删除的当前章节'],
      [after],
    ]);
    final current = _book('v2', [
      [before],
      ['另一章无关的文字'],
      [after],
    ]);
    final result = _relocate(old, current, old.anchorAt(1, 5)!, progress: true);
    // 前后两章夹定同路径候选，允许章节内近似；不会声称文字已验证。
    expect(result.status, 'approximate');
    expect(result.current!.start.spineIndex, 1);
    final removed = _book('v2', [
      [before],
      [after],
    ]);
    final fallback = _relocate(
      old,
      removed,
      old.anchorAt(1, 5)!,
      progress: true,
    );
    expect(fallback.current!.start.spineIndex, 1);
    expect(fallback.current!.start.charOffset, 0);
  });

  test('进度缺后章时用前章末尾，均缺失时首个可读章', () {
    final old = _book('v1', [
      [before],
      ['失去的正文'],
    ]);
    final one = _book('v2', [
      [before],
    ]);
    final previous = _relocate(old, one, old.anchorAt(1, 3)!, progress: true);
    expect(previous.status, 'approximate');
    expect(previous.current!.start.charOffset, before.length);
    final onlyNew = AnchorBook(
      revision: 'v3',
      chapters: [
        _chapter(0, ['封面文字'], readable: false),
        _chapter(1, ['全新可读正文']),
      ],
    );
    final first = _relocate(old, onlyNew, old.anchorAt(1, 3)!, progress: true);
    expect(first.current!.start.spineIndex, 1);
    expect(first.current!.start.charOffset, 0);
  });

  test('待确认后再次找到原文保留首次原始证据', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final removed = _book('v2', [
      [before + after],
    ]);
    final original = _range(old, 0, quote);
    final pending = _relocate(old, removed, original);
    final restored = _book('v3', [
      ['新增正文'],
      [before + quote + after],
    ]);
    final result = RevisionRelocator.relocate(
      oldBook: removed,
      newBook: restored,
      record: pending,
    );
    expect(result.status, 'relocated');
    expect(result.original, same(original));
    expect(restored.textFor(result.current!), quote);
    final repeated = RevisionRelocator.relocate(
      oldBook: restored,
      newBook: restored,
      record: result,
    );
    expect(repeated.status, 'verified');
    expect(repeated.original, same(original));
  });

  test('失败保留最近成功锚点，原始 JSON 不被覆盖', () {
    final old = _book('v1', [
      [before + quote + after],
    ]);
    final updated = _book('v2', [
      ['序言'],
      [before + quote + after],
    ]);
    final moved = _relocate(old, updated, _range(old, 0, quote));
    final gone = _book('v3', [
      ['全书文字均已删除并被改写'],
    ]);
    final pending = RevisionRelocator.relocate(
      oldBook: updated,
      newBook: gone,
      record: moved,
    );
    expect(pending.status, 'pending');
    expect(pending.current, same(moved.current));
    final decoded = AnchorRecord.decode(pending.encode())!;
    expect(decoded.original.toJson(), moved.original.toJson());
    expect(decoded.current!.toJson(), moved.current!.toJson());
    expect(decoded.isResolved, isFalse);
  });

  test('坏 JSON、未知版本和非法偏移安全拒绝', () {
    final book = _book('v1', [
      [quote],
    ]);
    final record = AnchorRecord(original: _range(book, 0, quote));
    expect(AnchorRecord.decode('broken'), isNull);
    expect(AnchorRecord.decode('{"version":2}'), isNull);
    final json = jsonDecode(record.encode()) as Map<String, dynamic>;
    final original = json['original'] as Map<String, dynamic>;
    final start = original['start'] as Map<String, dynamic>;
    start['charOffset'] = -1;
    expect(AnchorRecord.decode(jsonEncode(json)), isNull);
  });

  test('待核验选区只借候选坐标，不把错误文字当成证据', () {
    final book = _book('v2', [
      ['错误文字在原来偏移处'],
      [before + quote + after],
    ]);
    final anchor = book.rangeFromEvidence(
      startCfi: _cfi(0, 0).replaceFirst(')', ':9)'),
      endCfi: _cfi(0, 0),
      quote: quote,
      contextBefore: before,
      contextAfter: after,
    )!;
    final result = _relocate(book, book, anchor);
    expect(result.status, 'relocated');
    expect(result.current!.start.spineIndex, 1);
    expect(book.textFor(result.current!), quote);
    expect(anchor.start.chapterFingerprint, isEmpty);
    expect(
      book.rangeFromEvidence(
        startCfi: _cfi(0, 0),
        endCfi: _cfi(0, 0),
        quote: '',
      ),
      isNull,
    );
  });

  test('新增段落转在读，已有段落改字与纯分段不重置', () {
    final old = _book('v1', [
      [before, quote, after],
    ]);
    final changed = _book('v2', [
      [before, '作者修改的已有段落', after],
    ]);
    expect(RevisionRelocator.hasAddedReadableContent(old, changed), isFalse);
    final added = _book('v2', [
      [before, quote, '新插入的可读段落', after],
    ]);
    expect(RevisionRelocator.hasAddedReadableContent(old, added), isTrue);
    final split = _book('v2', [
      [before.substring(0, 10), before.substring(10), quote, after],
    ]);
    expect(RevisionRelocator.hasAddedReadableContent(old, split), isFalse);
    final movedSplit = _book('v2', [
      [after],
      [before.substring(0, 10), before.substring(10), quote],
    ]);
    expect(RevisionRelocator.hasAddedReadableContent(old, movedSplit), isFalse);
    final addedAndDeleted = _book('v2', [
      [before],
      ['全新序言'],
    ]);
    expect(
      RevisionRelocator.hasAddedReadableContent(old, addedAndDeleted),
      isTrue,
    );
  });

  test('非可读资源不影响读完状态', () {
    final old = _book('v1', [
      [before],
    ]);
    final current = AnchorBook(
      revision: 'v2',
      chapters: [
        _chapter(0, [before]),
        _chapter(1, ['封面或版权资源'], readable: false),
      ],
    );
    expect(RevisionRelocator.hasAddedReadableContent(old, current), isFalse);
  });

  test('增加重复段落或完全相同新章节仍是新增可读内容', () {
    final old = _book('v1', [
      [before, quote, after],
    ]);
    final repeated = _book('v2', [
      [before, quote, quote, after],
    ]);
    expect(RevisionRelocator.hasAddedReadableContent(old, repeated), isTrue);
    final repeatedChapter = _book('v2', [
      [before, quote, after],
      [before, quote, after],
    ]);
    expect(
      RevisionRelocator.hasAddedReadableContent(old, repeatedChapter),
      isTrue,
    );
  });
}
