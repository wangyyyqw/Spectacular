import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';

void main() {
  test('§47.3 的 9 类输入', () {
    const samples = <String>[
      'epubcfi(/6/4[chap01]!/4/2/1:0)',
      'epubcfi(/6/4/2/1:5)',
      'epubcfi(/6/4!/4/2,/2/1:0,/3/1:5)',
      'epubcfi(/6/4[chap^/01]!/4/2)',
      'epubcfi(/6/4!/4/2/1:3[;s=b])',
      'epubcfi(/6/4!/4/2/1:3~3.5)',
      'epubcfi(/6/4!/4/2/1:3@2:1)',
      'epubcfi(/6/4!/4)',
      'epubcfi(/6/4[chap01]!/4/2/1:0)',
    ];
    for (final value in samples) {
      expect(EpubCfi.parse(value), isNotNull, reason: value);
    }
    final escaped = EpubCfi.parse(samples[3])!;
    expect(escaped.itemrefAssertion, 'chap/01');
    expect(escaped.serialize(), samples[3]);
    expect(EpubCfi.parse(samples[4])!.side, CfiSide.before);
    expect(EpubCfi.parse(samples[4])!.serialize(), samples[4]);
    expect(EpubCfi.parse(samples[5])!.charOffset, 3);
    expect(EpubCfi.parse(samples[6])!.charOffset, 3);
  });

  test('范围形式解析、序列化与包含', () {
    const value = 'epubcfi(/6/4!/4/2,/2/1:0,/3/1:5)';
    final range = EpubCfi.parse(value)!;
    expect(range.isRange, isTrue);
    expect(range.serialize(), value);
    expect(range.rangeStart!.serialize(), 'epubcfi(/6/4!/4/2/2/1:0)');
    expect(range.rangeEnd!.serialize(), 'epubcfi(/6/4!/4/2/3/1:5)');

    final inside = EpubCfi.parse('epubcfi(/6/4!/4/2/2/1:2)')!;
    final before = EpubCfi.parse('epubcfi(/6/4!/4/2/1:9)')!;
    final after = EpubCfi.parse('epubcfi(/6/4!/4/2/4/1:0)')!;
    expect(range.contains(inside), isTrue);
    expect(range.contains(before), isFalse);
    expect(range.contains(after), isFalse);
  });

  test('构造器与序列化对称', () {
    final cfi = CfiBuilder()
        .itemRef(4, assertion: 'ch1')
        .body(4, assertion: 'body1')
        .step(2)
        .step(1, assertion: 'p1')
        .charOffset(3)
        .side(CfiSide.after)
        .build();
    expect(cfi.serialize(), 'epubcfi(/6/4[ch1]!/4[body1]/2/1[p1]:3[;s=a])');
    final parsed = EpubCfi.parse(cfi.serialize())!;
    expect(parsed.itemref, 4);
    expect(parsed.itemrefAssertion, 'ch1');
    expect(parsed.body, 4);
    expect(parsed.charOffset, 3);
    expect(parsed.side, CfiSide.after);
    expect(parsed.compareTo(cfi), 0);
  });

  test('copyWithSide 不改变步骤', () {
    final cfi = EpubCfi.parse('epubcfi(/6/4!/4/2/1:5)')!;
    final before = cfi.copyWithSide(CfiSide.before);
    final after = cfi.copyWithSide(CfiSide.after);
    expect(before.serialize(), 'epubcfi(/6/4!/4/2/1:5[;s=b])');
    expect(after.serialize(), 'epubcfi(/6/4!/4/2/1:5[;s=a])');
    expect(before.charOffset, 5);
    expect(after.compareTo(before), greaterThan(0));
  });

  test('20 个畸形输入返回 null', () {
    const invalid = <String>[
      '',
      'epubcfi',
      'epubcfi()',
      'epubcfi(',
      'epubcfi(/6/4',
      'EPUBCFI(/6/4)',
      ' epubcfi(/6/4)',
      'epubcfi(/a/4)',
      'epubcfi(/6/)',
      'epubcfi(//4)',
      'epubcfi(/6/4[abc)',
      'epubcfi(/6/4[abc)!/4',
      'epubcfi(/6/4:abc)',
      'epubcfi(/6/4!)',
      'epubcfi(!/6/4)',
      'epubcfi(,)',
      'epubcfi(/6/4,,)',
      'epubcfi(/6/4,/2,/3',
      'epubcfi(/6/4,/2/x,/3)',
      'epubcfi(/6/4!/4:3[;s=x])',
    ];
    for (final value in invalid) {
      expect(EpubCfi.parse(value), isNull, reason: '应判为非法：$value');
    }
  });

  test('比较满足全序并支持随机组合', () {
    final values = <String>[
      'epubcfi(/6/2!/4/2/1:0)',
      'epubcfi(/6/2!/4/2/1:3)',
      'epubcfi(/6/2!/4/2/1:3[;s=b])',
      'epubcfi(/6/2!/4/2/1:3[;s=a])',
      'epubcfi(/6/4!/4/2/1:0)',
      'epubcfi(/6/4!/4/2,/2/1:0,/3/1:5)',
      'epubcfi(/6/4!/4/2/2/1:2)',
    ];
    final parsed = values.map(EpubCfi.parse).toList();
    for (final cfi in parsed) {
      expect(cfi!.compareTo(cfi), 0);
    }
    for (var i = 0; i < parsed.length; i++) {
      for (var j = 0; j < parsed.length; j++) {
        expect(
          parsed[i]!.compareTo(parsed[j]!).sign,
          -parsed[j]!.compareTo(parsed[i]!).sign,
        );
      }
    }
    for (var i = 0; i < parsed.length; i++) {
      for (var j = 0; j < parsed.length; j++) {
        for (var k = 0; k < parsed.length; k++) {
          if (parsed[i]!.compareTo(parsed[j]!) <= 0 &&
              parsed[j]!.compareTo(parsed[k]!) <= 0) {
            expect(parsed[i]!.compareTo(parsed[k]!), lessThanOrEqualTo(0));
          }
        }
      }
    }
  });
}
