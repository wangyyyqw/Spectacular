import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';

void main() {
  test('随机 200 组 CFI 满足全序', () {
    final random = Random(42);
    final cfis = <EpubCfi>[];
    for (var i = 0; i < 200; i++) {
      final builder = CfiBuilder()
          .itemRef((1 + random.nextInt(20)) * 2)
          .body(4);
      final depth = 1 + random.nextInt(3);
      for (var d = 0; d < depth; d++) {
        builder.step((1 + random.nextInt(5)) * 2);
      }
      if (random.nextBool()) {
        builder.charOffset(random.nextInt(100));
      }
      builder.side(CfiSide.values[random.nextInt(CfiSide.values.length)]);
      final cfi = EpubCfi.parse(builder.build().serialize());
      expect(cfi, isNotNull, reason: '第 $i 组');
      cfis.add(cfi!);
    }

    for (final cfi in cfis) {
      expect(cfi.compareTo(cfi), 0);
    }
    for (var i = 0; i < cfis.length; i++) {
      for (var j = 0; j < cfis.length; j++) {
        expect(
          cfis[i].compareTo(cfis[j]).sign,
          -cfis[j].compareTo(cfis[i]).sign,
          reason: '反对称失败：$i / $j',
        );
      }
    }
    for (var n = 0; n < 200; n++) {
      final i = random.nextInt(cfis.length);
      final j = random.nextInt(cfis.length);
      final k = random.nextInt(cfis.length);
      if (cfis[i].compareTo(cfis[j]) <= 0 && cfis[j].compareTo(cfis[k]) <= 0) {
        expect(cfis[i].compareTo(cfis[k]), lessThanOrEqualTo(0));
      }
    }
  });

  test('构造器 indirection 生成多段并 round-trip', () {
    final cfi = CfiBuilder()
        .itemRef(4)
        .body(4)
        .step(2)
        .indirection()
        .step(2)
        .step(1)
        .build();
    final serialized = cfi.serialize();
    expect(serialized, 'epubcfi(/6/4!/4/2!/2/1)');
    expect(EpubCfi.parse(serialized)!.serialize(), serialized);
  });
}
