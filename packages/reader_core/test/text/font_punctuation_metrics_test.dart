import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/font_punctuation_metrics.dart';

Uint8List _fixture() =>
    File('test/fixtures/fonts/NoHaltPunctuation.ttf').readAsBytesSync();

int _tableStart(Uint8List bytes, String tag) {
  final data = ByteData.sublistView(bytes);
  final code = tag.codeUnits.fold(0, (value, unit) => (value << 8) | unit);
  for (var i = 0; i < data.getUint16(4); i++) {
    final record = 12 + i * 16;
    if (data.getUint32(record) == code) {
      return data.getUint32(record + 8);
    }
  }
  throw StateError('自建夹具缺少 $tag 表');
}

FontPunctuationMetrics? _lookup(
  String family,
  String glyph, {
  int weight = 300,
  bool italic = false,
}) => FontPunctuationRegistry.lookup(
  family,
  glyph.codeUnitAt(0),
  weight: weight,
  italic: italic,
);

void main() {
  test('读取真实侧留白，重复登记相同度量不改变 revision', () {
    final bytes = _fixture();
    const family = 'PunctuationMetricsRatios';
    final revision = FontPunctuationRegistry.revision;
    FontPunctuationRegistry.register(family, bytes, weight: 300, italic: false);
    expect(FontPunctuationRegistry.revision, revision + 1);
    for (final (glyph, left, right) in [
      ('，', .2, .65),
      ('“', .65, .2),
      ('！', 0.0, 0.0),
    ]) {
      final metrics = _lookup(family, glyph)!;
      expect(metrics.advanceRatio, 1);
      expect(metrics.leftBearingRatio, closeTo(left, .0001));
      expect(metrics.rightBearingRatio, closeTo(right, .0001));
    }
    FontPunctuationRegistry.register(
      family,
      Uint8List.fromList(bytes),
      weight: 300,
      italic: false,
    );
    expect(FontPunctuationRegistry.revision, revision + 1);
    expect(_lookup(family, '甲'), isNull, reason: '只登记标点，不把正文误作候选');
  });

  test('截断和损坏度量表安全拒绝，不向调用方抛解析异常', () {
    final bytes = _fixture();
    final brokenTable = Uint8List.fromList(bytes);
    ByteData.sublistView(brokenTable)
        .setUint16(_tableStart(brokenTable, 'hhea') + 34, 0);
    final cases = [Uint8List.sublistView(bytes, 0, 20), brokenTable];
    for (var i = 0; i < cases.length; i++) {
      final family = 'PunctuationMetricsBroken$i';
      expect(
        () => FontPunctuationRegistry.register(
          family,
          cases[i],
          weight: 300,
          italic: false,
        ),
        returnsNormally,
      );
      expect(_lookup(family, '，'), isNull);
    }
  });

  test('非匹配斜体、合成粗体及伪造登记字重不能借用普通字面', () {
    const family = 'PunctuationMetricsStyle';
    final bytes = _fixture();
    FontPunctuationRegistry.register(family, bytes, weight: 300, italic: false);
    expect(_lookup(family, '，', italic: true), isNull);
    expect(_lookup(family, '，', weight: 700), isNull);
    FontPunctuationRegistry.register(
      'PunctuationMetricsSyntheticBold',
      bytes,
      weight: 700,
      italic: false,
    );
    expect(
      _lookup('PunctuationMetricsSyntheticBold', '，', weight: 700),
      isNull,
    );
  });

  test('多字面包含未知解析结果或缺少精确候选时拒绝猜测', () {
    const uncertain = 'PunctuationMetricsUncertain';
    final bytes = _fixture();
    FontPunctuationRegistry.register(
      uncertain,
      bytes,
      weight: 300,
      italic: false,
    );
    FontPunctuationRegistry.register(
      uncertain,
      Uint8List.sublistView(bytes, 0, 20),
      weight: 700,
      italic: false,
    );
    expect(_lookup(uncertain, '，'), isNull);
    const known = 'PunctuationMetricsKnownFaces';
    final regular = Uint8List.fromList(bytes);
    ByteData.sublistView(regular)
        .setUint16(_tableStart(regular, 'OS/2') + 4, 400);
    FontPunctuationRegistry.register(known, bytes, weight: 300, italic: false);
    FontPunctuationRegistry.register(
      known,
      regular,
      weight: 400,
      italic: false,
    );
    expect(_lookup(known, '，'), isNotNull);
    expect(_lookup(known, '，', weight: 500), isNull);
  });
}
