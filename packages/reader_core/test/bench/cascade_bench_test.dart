import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';

class _Element implements SelectorElement {
  @override
  String get tag => 'p';
  @override
  Map<String, String> get attributes => const {'class': 'body'};
  @override
  List<SelectorElement> get childElements => const [];
}

double _median(void Function() action) {
  action();
  final samples = <double>[];
  for (var i = 0; i < 5; i++) {
    final watch = Stopwatch()..start();
    action();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return samples[2];
}

void main() {
  test('规则预编译与逐元素排序的样式阶段基准', () {
    final sheet = CssParser.parse('''
      ${[for (var i = 0; i < 600; i++) '.unused$i { margin-left: ${i}px; }'].join()}
      p.body { font-size: 18px; line-height: 1.5; }
      p:not(.skip) { color: #333333; }
    ''');
    final rules = CascadeRule.fromStylesheet(
      sheet,
      origin: CascadeOrigin.author,
    );
    final compiled = CascadeRuleSet(rules);
    final element = _Element();
    void compute(List<CascadeRule> candidates) {
      for (var i = 0; i < 400; i++) {
        final style = Cascade.compute(
          element: element,
          ancestors: [],
          rules: candidates,
        );
        expect(style.fontSize, 18);
      }
    }

    final rawMs = _median(() => compute(rules));
    final compiledMs = _median(() => compute(compiled.candidatesFor(element)));
    // 只记录耗时，不把受 JIT、机器负载影响的比值作为正确性门禁。
    // ignore: avoid_print
    print(
      '样式基准：原始规则 ${rawMs.toStringAsFixed(2)}ms，'
      '预编译候选 ${compiledMs.toStringAsFixed(2)}ms，'
      '候选 ${compiled.candidatesFor(element).length}/${rules.length}',
    );
  }, skip: Platform.environment['CASCADE_BENCH'] != '1');
}
