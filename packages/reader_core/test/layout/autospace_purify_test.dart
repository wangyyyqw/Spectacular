import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/autospace.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/text/text_purify.dart';

/// P7-20：中西文自动间距与空格整理。
void main() {
  group('autospaceOffsets 纯函数', () {
    test('CJK↔拉丁双向边界计入', () {
      // 中(0)文(1)A(2) → 边界在 1（文|A）；A(2)b(3)c(4)中(5) → 边界在 4。
      expect(autospaceOffsets('中文Abc中'), <int>[1, 4]);
    });

    test('数字边界计入、标点与换行不计入', () {
      // 第(0)3(1)章(2)：第|3 与 3|章 都是边界。
      expect(autospaceOffsets('第3章'), <int>[0, 1]);
      // ，为全角标点，不在 CJK 表意范围 → 与 A 相邻不算边界。
      expect(autospaceOffsets('，A'), isEmpty);
      expect(autospaceOffsets('中\nA'), isEmpty, reason: '换行跳过');
    });

    test('纯中文或纯西文无边界', () {
      expect(autospaceOffsets('中文中文'), isEmpty);
      expect(autospaceOffsets('Abc123'), isEmpty);
    });
  });

  group('测量集成（TextLayoutEngine）', () {
    final normal = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final autospaceOn = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'text-autospace': 'normal',
    });

    test('启用后行宽增加 0.125em × 边界数', () {
      const text = '中文Abc中';
      final off = TextLayoutEngine.layout(
        text: text,
        style: normal,
        maxWidth: 400,
      );
      final on = TextLayoutEngine.layout(
        text: text,
        style: autospaceOn,
        maxWidth: 400,
      );
      expect(off.lineCount, 1);
      expect(on.lineCount, 1);
      // 两个边界 × 0.125em × 16px = 4px。
      expect(on.lines.single.width, closeTo(off.lines.single.width + 4, 0.01));
    });

    test('默认 none 与现状一致；解析与继承', () {
      const text = '中文Abc中';
      final off = TextLayoutEngine.layout(
        text: text,
        style: normal,
        maxWidth: 400,
      );
      expect(off.lines.single.width, 6 * 16.0);
      expect(normal.textAutospace, CssTextAutospace.none);
      expect(autospaceOn.textAutospace, CssTextAutospace.normal);
      expect(
        ComputedStyle(const <String, String>{
          'font-size': '16px',
          'text-autospace': 'no-autospace',
        }).textAutospace,
        CssTextAutospace.none,
      );
      final child = ComputedStyle(
        const <String, String>{'color': 'red'},
        parent: autospaceOn,
        explicitProperties: const <String>{'color'},
      );
      expect(child.textAutospace, CssTextAutospace.normal);
    });
  });

  group('purifySpaces 空格整理（白名单）', () {
    test('半角标点在 CJK 上下文转全角', () {
      expect(purifySpaces('你好,世界!'), '你好，世界！');
      expect(purifySpaces('(你好)'), '（你好）');
      expect(purifySpaces('注意:内容;结束'), '注意：内容；结束');
    });

    test('数字保护：3.14 与 1,000 不转换', () {
      expect(purifySpaces('圆周率是3.14没错'), '圆周率是3.14没错');
      expect(purifySpaces('共1,000册'), '共1,000册');
    });

    test('映射外符号与空格原样保留', () {
      expect(purifySpaces('温度～20 = 好 / 全部'), '温度～20 = 好 / 全部');
      expect(purifySpaces('你好 , 世界'), '你好 ， 世界', reason: '空格保留只转标点');
      expect(purifySpaces('a - b'), 'a - b');
    });

    test('纯西文上下文不转换', () {
      expect(purifySpaces('Hello, world!'), 'Hello, world!');
    });

    test('换行与空行原样（不改换行）', () {
      expect(purifySpaces('第一段,\n第二段!'), '第一段，\n第二段！');
    });
  });
}
