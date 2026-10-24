import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/layout/cjk_justify.dart';

const _cjkFamily = 'P202Align';

ComputedStyle _style({String? align, String? indent, String family = 'Ahem'}) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': family,
      'text-align': ?align,
      'text-indent': ?indent,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    if (!file.existsSync()) {
      return;
    }
    final bytes = ByteData.view(file.readAsBytesSync().buffer);
    final loader = FontLoader(_cjkFamily)
      ..addFont(Future<ByteData>.value(bytes));
    await loader.load();
  });

  test('left 与 start 对齐都在内容区左边缘', () {
    for (final align in ['left', 'start']) {
      final layout = TextLayoutEngine.layout(
        text: 'abcdef',
        style: _style(align: align),
        maxWidth: 200,
      );
      expect(layout.lines.single.offsetX, 0);
      expect(layout.lines.single.justifyExtra, 0);
    }
  });

  test('center 对齐按余量一半偏移', () {
    final layout = TextLayoutEngine.layout(
      text: 'abc',
      style: _style(align: 'center'),
      maxWidth: 200,
    );
    // Ahem 单字 16px：行宽 48，余量 152，偏移 76。
    expect(layout.lines.single.width, closeTo(48, 0.01));
    expect(layout.lines.single.offsetX, closeTo(76, 0.01));
  });

  test('right 与 end 对齐贴右边缘', () {
    for (final align in ['right', 'end']) {
      final layout = TextLayoutEngine.layout(
        text: 'abc',
        style: _style(align: align),
        maxWidth: 200,
      );
      expect(layout.lines.single.offsetX, closeTo(152, 0.01));
    }
  });

  test('多行按行各自对齐', () {
    final layout = TextLayoutEngine.layout(
      text: 'abc\na',
      style: _style(align: 'right'),
      maxWidth: 200,
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].offsetX, closeTo(200 - 48, 0.01));
    expect(layout.lines[1].offsetX, closeTo(200 - 16, 0.01));
  });

  test('justify 纯中文按间隙分摊，末行不拉伸', () {
    final layout = TextLayoutEngine.layout(
      text: '中文两端对齐样本内容用于验证末行不拉伸效果',
      style: _style(align: 'justify', family: _cjkFamily),
      maxWidth: 150,
    );
    expect(layout.lineCount, greaterThan(1));
    for (final line in layout.lines.take(layout.lineCount - 1)) {
      expect(line.justifyExtra, greaterThan(0));
      expect(line.offsetX, 0);
      expect(
        line.justifyExtra,
        closeTo(150 - line.width, 0.01),
        reason: '余量等于可用宽减行宽',
      );
    }
    expect(layout.lines.last.justifyExtra, 0);
    expect(layout.lines.last.isLastLine, isTrue);
  });

  test('justify 末行余量不参与分摊', () {
    final layout = TextLayoutEngine.layout(
      text: '中文对齐',
      style: _style(align: 'justify', family: _cjkFamily),
      maxWidth: 400,
    );
    expect(layout.lineCount, 1);
    expect(layout.lines.single.justifyExtra, 0);
    expect(layout.lines.single.offsetX, 0);
  });

  test('justify 硬换行行不拉伸', () {
    final layout = TextLayoutEngine.layout(
      text: '中文\n对齐',
      style: _style(align: 'justify', family: _cjkFamily),
      maxWidth: 400,
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].isHardBreak, isTrue);
    expect(layout.lines[0].justifyExtra, 0);
    expect(layout.lines[1].justifyExtra, 0);
  });

  test('justify 西文行拉伸词间空格', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab cd ef gh ij kl mn',
      style: _style(align: 'justify'),
      maxWidth: 100,
    );
    expect(layout.lineCount, greaterThan(1));
    for (final line in layout.lines.take(layout.lineCount - 1)) {
      final lineText = layout.text.substring(line.start, line.end);
      expect(cjkJustifyGapOffsets(lineText), isNotEmpty);
      expect(line.justifyExtra, greaterThan(0));
    }
    expect(layout.lines.last.justifyExtra, 0);
  });

  test('justify 无可拉伸间隙的行不拉伸', () {
    // 单个长英文单词没有词间空格，不能拆词内字距。
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(align: 'justify'),
      maxWidth: 100,
    );
    expect(layout.lineCount, 1);
    expect(layout.lines.single.justifyExtra, 0);
  });

  test('justify 首行缩进按减宽后的余量分摊', () {
    final layout = TextLayoutEngine.layout(
      text: '中文两端对齐样本内容用于验证首行缩进',
      style: _style(align: 'justify', indent: '32px', family: _cjkFamily),
      maxWidth: 150,
    );
    final first = layout.lines.first;
    expect(first.indent, 32);
    expect(first.offsetX, 32);
    expect(first.justifyExtra, closeTo(150 - 32 - first.width, 0.01));
    expect(first.justifyExtra, greaterThan(0));
  });

  test('center 与 right 在首行缩进下仍贴内容区右侧', () {
    final centered = TextLayoutEngine.layout(
      text: 'abc',
      style: _style(align: 'center', indent: '32px'),
      maxWidth: 200,
    );
    final right = TextLayoutEngine.layout(
      text: 'abc',
      style: _style(align: 'right', indent: '32px'),
      maxWidth: 200,
    );
    expect(
      centered.lines.single.offsetX,
      closeTo(32 + (200 - 32 - 48) / 2, 0.01),
    );
    expect(right.lines.single.offsetX, closeTo(200 - 48, 0.01));
  });

  test('无限宽测量不做对齐偏移', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(align: 'right'),
      maxWidth: double.infinity,
    );
    expect(layout.lines.single.offsetX, 0);
  });
}
