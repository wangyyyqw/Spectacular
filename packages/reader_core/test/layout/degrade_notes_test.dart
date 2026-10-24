import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// P2-34 降级固定用例：P0 矩阵里标注「部分」的属性当前不参与块流/文本布局，
/// 这里显式固定「已解析但不消费」的行为，避免静默变化。
/// 对应缺陷清单：`方案/验收记录/P2-34-排版边界缺陷清单.md`。
ComputedStyle _style(Map<String, String> extra) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...extra,
    });

const _text = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz';

void main() {
  test('float 已在块流分派，但纯文本行布局不产生环绕（P3 浮动带）', () {
    final plain = TextLayoutEngine.layout(
      text: _text,
      style: _style(const {}),
      maxWidth: 160,
    );
    final floated = TextLayoutEngine.layout(
      text: _text,
      style: _style(const {'float': 'left'}),
      maxWidth: 160,
    );
    expect(floated.lineCount, plain.lineCount);
    for (var i = 0; i < plain.lineCount; i++) {
      expect(floated.lines[i].width, closeTo(plain.lines[i].width, 0.01));
      expect(floated.lines[i].start, plain.lines[i].start);
      expect(floated.lines[i].end, plain.lines[i].end);
    }
  });

  test('clear 与 top/left 已解析，不影响文本行布局（P3 绝对定位）', () {
    final plain = TextLayoutEngine.layout(
      text: _text,
      style: _style(const {}),
      maxWidth: 160,
    );
    final offset = TextLayoutEngine.layout(
      text: _text,
      style: _style(const {
        'clear': 'both',
        'position': 'absolute',
        'top': '10px',
        'left': '12px',
      }),
      maxWidth: 160,
    );
    expect(offset.lineCount, plain.lineCount);
    expect(offset.width, closeTo(plain.width, 0.01));
    expect(offset.lines.first.end, plain.lines.first.end);
  });

  test('border-collapse/border-spacing 已解析，不改变块文本布局（P3-18 表格）', () {
    final plain = TextLayoutEngine.layout(
      text: _text,
      style: _style(const {}),
      maxWidth: 160,
    );
    final tableish = TextLayoutEngine.layout(
      text: _text,
      style: _style(const {
        'border-collapse': 'collapse',
        'border-spacing': '6px 8px',
      }),
      maxWidth: 160,
    );
    expect(tableish.lineCount, plain.lineCount);
    expect(tableish.height, closeTo(plain.height, 0.01));
  });

  test('降级属性不改变分页结果', () {
    final plain = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final degraded = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'float': 'left',
      'clear': 'both',
      'border-collapse': 'collapse',
    });
    final a = TextLayoutEngine.layout(text: _text, style: plain, maxWidth: 160);
    final b = TextLayoutEngine.layout(
      text: _text,
      style: degraded,
      maxWidth: 160,
    );
    expect(b.lineCount, a.lineCount);
    expect(b.height, closeTo(a.height, 0.01));
  });
}
