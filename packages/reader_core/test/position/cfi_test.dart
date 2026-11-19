import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/toc_cfi.dart';
import 'package:reader_core/position/cfi.dart';

import '../support/corpus.dart';

const List<String> _samples = <String>[
  'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)',
  'epubcfi(/6/2!/4/2/2:0)',
  'epubcfi(/6/14[chapter03]!/4/2/2/2[para1]/1:5)',
  'epubcfi(/6/4!/4/10/2[c01]/8/1:3)',
  'epubcfi(/6/4!/4/2/2/2/4/2/2[note1]:7)',
  'epubcfi(/6/8!/4/2/6/2[img1])',
  'epubcfi(/6/4[cover]!/2/2[titlepage])',
  'epubcfi(/6/10!/4/2/4/2/2/1:0)',
  'epubcfi(/6/12!/4/2/2[preface]!/4/2/2:1)',
  'epubcfi(/6/2[title]!/2/2/2/2/2)',
];

void main() {
  test('10 个真实 CFI 解析并 round-trip 无损', () {
    for (final sample in _samples) {
      final parsed = EpubCfi.parse(sample);
      expect(parsed, isNotNull, reason: '解析失败：$sample');
      expect(parsed!.serialize(), sample, reason: 'round-trip 不一致：$sample');
    }
  });

  test('非法输入返回 null 而不抛异常', () {
    const invalid = <String>[
      '',
      'epubcfi()',
      'foo(/6/4)',
      'epubcfi(/a/4)',
      'epubcfi(/6/4!)',
      'epubcfi(/6/4:abc)',
      'epubcfi(/6/4[unclosed)',
      'epubcfi(!/6/4)',
    ];
    for (final value in invalid) {
      expect(EpubCfi.parse(value), isNull, reason: '应判为非法：$value');
    }
  });

  test('缺省间接引用补全后保留字符偏移', () {
    final candidates = epubCfiCandidates('epubcfi(/6/4/4/2/1:12)').toList();
    expect(candidates.first, 'epubcfi(/6/4!/4/2/1:12)');
    expect(EpubCfi.parse(candidates.first)!.charOffset, 12);
    expect(candidates, contains('epubcfi(/6/4/4/2/1:12)'));
  });

  test('序列化 100 次结果稳定', () {
    final parsed = EpubCfi.parse(_samples.first)!;
    final first = parsed.serialize();
    for (var i = 0; i < 100; i++) {
      expect(parsed.serialize(), first);
    }
  });

  test('比较满足自反、反对称与传递', () {
    final cfis = _samples.map(EpubCfi.parse).toList();
    for (final cfi in cfis) {
      expect(cfi!.compareTo(cfi), 0);
    }
    for (var i = 0; i < cfis.length; i++) {
      for (var j = 0; j < cfis.length; j++) {
        final forward = cfis[i]!.compareTo(cfis[j]!);
        final backward = cfis[j]!.compareTo(cfis[i]!);
        expect(forward.sign, -backward.sign);
      }
    }
    for (var i = 0; i < cfis.length; i++) {
      for (var j = 0; j < cfis.length; j++) {
        for (var k = 0; k < cfis.length; k++) {
          if (cfis[i]!.compareTo(cfis[j]!) <= 0 &&
              cfis[j]!.compareTo(cfis[k]!) <= 0) {
            expect(cfis[i]!.compareTo(cfis[k]!), lessThanOrEqualTo(0));
          }
        }
      }
    }
  });

  test('真实书目录绑定的 CFI round-trip 与序列化稳定', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      return;
    }
    final opened = await openEpub(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final document = opened.document!;
    final bound = TocCfiBinder.bind(
      archive: document.archive,
      spine: document.spine,
      opfPath: document.opfPath,
      toc: document.toc,
      maxEntries: 20,
    );
    final cfis = bound.toc
        .map((entry) => entry.cfi)
        .whereType<EpubCfi>()
        .take(10)
        .toList();
    expect(cfis, hasLength(10));
    for (final cfi in cfis) {
      final text = cfi.serialize();
      final reparsed = EpubCfi.parse(text);
      expect(reparsed, isNotNull, reason: text);
      expect(reparsed!.serialize(), text);
      expect(reparsed.compareTo(cfi), 0);
      for (var i = 0; i < 100; i++) {
        expect(cfi.serialize(), text);
      }
    }
  });

  test('范围/转义/side 的 parse→serialize→parse 语义一致', () {
    const values = <String>[
      'epubcfi(/6/4!/4/2/1:3[;s=b])',
      'epubcfi(/6/4!/4/2/1:3[;s=a])',
      'epubcfi(/6/4[chap^/01]!/4/2)',
      'epubcfi(/6/4!/4/2,/2/1:0,/3/1:5)',
    ];
    for (final value in values) {
      final first = EpubCfi.parse(value)!;
      final second = EpubCfi.parse(first.serialize())!;
      expect(second.serialize(), first.serialize());
      expect(second.compareTo(first), 0);
      expect(second.spine, first.spine);
      expect(second.itemref, first.itemref);
      expect(second.body, first.body);
      expect(second.side, first.side);
      expect(
        second.steps.map((step) => step.toCfi()).toList(),
        first.steps.map((step) => step.toCfi()).toList(),
      );
      if (first.isRange) {
        expect(second.rangeStart!.serialize(), first.rangeStart!.serialize());
        expect(second.rangeEnd!.serialize(), first.rangeEnd!.serialize());
      }
      for (var i = 0; i < 100; i++) {
        expect(first.serialize(), first.serialize());
      }
    }
  });
}
