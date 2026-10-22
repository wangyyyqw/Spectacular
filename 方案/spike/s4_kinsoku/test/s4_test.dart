// S4 实验：Flutter 文本引擎的中文避头尾（禁则）行为
//
// 运行：flutter test test/s4_test.dart
// 输出：控制台表格 + s4-result.json
//
// 说明：flutter_test 默认只有 Ahem 字体，所有字形等宽，无法反映真实中英混排宽度。
// 这里加载参考工程里的 Source Han Serif SC（OFL）作为正文测量字体。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String kFontPath =
    '../../../test_fonts/SourceHanSerifSC-Regular.otf';
const String kFontFamily = 'S4CJK';
const double kFontSize = 16;

const String kStartForbidden = '，。、；：？！';
const String kStartForbiddenClose = '）」』】》';
const String kEndForbiddenOpen = '（「『【《〈';

late double unitWidth;

Future<void> _loadFont() async {
  final file = File(kFontPath);
  expect(file.existsSync(), isTrue, reason: '字体不存在：$kFontPath');
  final bytes = await file.readAsBytes();
  final loader = FontLoader(kFontFamily)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

TextPainter _layout(String text, double maxWidth) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: kFontSize,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
    locale: const Locale('zh', 'CN'),
  )..layout(maxWidth: maxWidth);
}

/// 逐行取文本：getLineBoundary 给出当前行覆盖的字符区间。
List<String> _linesOf(TextPainter painter, String text) {
  final count = painter.computeLineMetrics().length;
  final result = <String>[];
  var start = 0;
  for (var i = 0; i < count && start < text.length; i++) {
    final range = painter.getLineBoundary(TextPosition(offset: start));
    var end = range.end;
    if (end <= start) end = start + 1;
    if (end > text.length) end = text.length;
    result.add(text.substring(start, end));
    start = end;
  }
  return result;
}

String _visibleFirst(String line) {
  for (final r in line.runes) {
    final c = String.fromCharCode(r);
    if (c.trim().isNotEmpty) return c;
  }
  return '';
}

String _visibleLast(String line) {
  final chars = line.runes.map(String.fromCharCode).where((c) => c.trim().isNotEmpty).toList();
  return chars.isEmpty ? '' : chars.last;
}


class CaseResult {
  CaseResult({
    required this.id,
    required this.title,
    required this.text,
    required this.widthUnits,
    required this.lines,
    required this.lineWidths,
    required this.didOverflow,
  });

  final String id;
  final String title;
  final String text;
  final double widthUnits;
  final List<String> lines;
  final List<double> lineWidths;
  final bool didOverflow;

  List<String> get firstChars => lines.map(_visibleFirst).toList();
  List<String> get lastChars => lines.map(_visibleLast).toList();

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'widthUnits': widthUnits,
        'maxWidth': widthUnits * unitWidth,
        'lines': lines,
        'lineWidths': lineWidths,
        'firstChars': firstChars,
        'lastChars': lastChars,
        'didOverflow': didOverflow,
      };
}

CaseResult _run({
  required String id,
  required String title,
  required String text,
  required double widthUnits,
}) {
  final maxWidth = widthUnits * unitWidth;
  final painter = _layout(text, maxWidth);
  final lines = _linesOf(painter, text);
  final metrics = painter.computeLineMetrics();
  final lineWidths = metrics
      .map((m) => double.parse(m.width.toStringAsFixed(2)))
      .toList();
  final overflow = lineWidths.any((w) => w > maxWidth + 0.01);
  return CaseResult(
    id: id,
    title: title,
    text: text,
    widthUnits: widthUnits,
    lines: lines,
    lineWidths: lineWidths,
    didOverflow: overflow,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont();
    final probe = TextPainter(
      text: const TextSpan(
        text: '中',
        style: TextStyle(fontFamily: kFontFamily, fontSize: kFontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitWidth = probe.width;
    print('单位宽（一个全角字）= ${unitWidth.toStringAsFixed(2)} 逻辑像素');
  });

  test('S4 十场景', () {
    final cases = <CaseResult>[
      _run(id: 'S4-1', title: '行首禁标点（，。、；：？！）', widthUnits: 10,
          text: '一二三四五六七八九十，后续文字继续排下去'),
      _run(id: 'S4-2', title: '行首禁后括号/后引号', widthUnits: 10,
          text: '一二三四五六七八九十」后续文字继续排下去'),
      _run(id: 'S4-3', title: '行尾禁前括号/前引号', widthUnits: 10,
          text: '一二三四五六七八九「引用文字继续排下去'),
      _run(id: 'S4-4', title: '「……」窄宽度（2 字）', widthUnits: 2,
          text: '「……」'),
      _run(id: 'S4-4b', title: '「……」窄宽度（3 字）', widthUnits: 3,
          text: '「……」'),
      _run(id: 'S4-4c', title: '「……」窄宽度（4 字）', widthUnits: 4,
          text: '「……」'),
      _run(id: 'S4-5', title: '数字 2026 不被拆开', widthUnits: 10,
          text: '一二三四五六七八九2026年继续排'),
      _run(id: 'S4-6', title: '英文单词按词断', widthUnits: 14,
          text: 'Hello wonderful internationalization'),
      _run(id: 'S4-7', title: '中英混排', widthUnits: 6,
          text: '中文English混排测试继续排'),
      _run(id: 'S4-8', title: '省略号 …… 不被拆开（10 字）', widthUnits: 10,
          text: '一二三四五六七八九……后续文字继续排'),
      _run(id: 'S4-8b', title: '省略号 …… 不被拆开（9 字）', widthUnits: 9,
          text: '一二三四五六七八九……后续文字继续排'),
      _run(id: 'S4-9', title: '破折号 —— 允许断在其后', widthUnits: 10,
          text: '一二三四五六七八九——后文继续排下去'),
      _run(id: 'S4-10', title: '长西文 URL 未设 word-break', widthUnits: 8,
          text: 'https://example.com/averylongpathsegment'),
    ];

    for (final c in cases) {
      print('--- ${c.id} ${c.title}');
      print('text: ${c.text}');
      print('width: ${(c.widthUnits * unitWidth).toStringAsFixed(1)} '
          '(= ${c.widthUnits} 字)');
      for (var i = 0; i < c.lines.length; i++) {
        print('  L${i + 1} [${c.firstChars[i]}] .. [${c.lastChars[i]}] '
            'w=${c.lineWidths[i]}  ${c.lines[i]}');
      }
      print('overflow: ${c.didOverflow}');
    }

    bool startsWithAny(CaseResult c, String set) =>
        c.firstChars.any((ch) => ch.isNotEmpty && set.contains(ch));

    bool endsWithAny(CaseResult c, String set) =>
        c.lastChars.any((ch) => ch.isNotEmpty && set.contains(ch));

    bool hasEmptyLine(CaseResult c) => c.lines.any((l) => l.trim().isEmpty);

    final byId = {for (final c in cases) c.id: c};

    final checks = <String, bool>{
      'S4-1 行首无禁标点': !startsWithAny(byId['S4-1']!, kStartForbidden),
      'S4-2 行首无后括号/后引号':
          !startsWithAny(byId['S4-2']!, kStartForbiddenClose),
      'S4-3 行尾无前括号/前引号':
          !endsWithAny(byId['S4-3']!, kEndForbiddenOpen),
      'S4-4 无空行首': !hasEmptyLine(byId['S4-4']!),
      'S4-5 2026 未拆开': !_digitSplit(byId['S4-5']!),
      'S4-8 省略号未拆开': !(<CaseResult>[
        byId['S4-4']!,
        byId['S4-4b']!,
        byId['S4-4c']!,
        byId['S4-8']!,
        byId['S4-8b']!,
      ].any(_ellipsisSplit)),
      'S4-9 破折号未拆开': !_dashSplit(byId['S4-9']!),
    };

    final output = {
      'environment': {
        'flutter': '3.47.5',
        'dart': '3.13.4',
        'platform': Platform.operatingSystem,
        'font': kFontPath,
        'fontFamily': kFontFamily,
        'fontSize': kFontSize,
        'unitWidth': unitWidth,
        'locale': 'zh_CN',
        'measuredAt': DateTime.now().toIso8601String(),
      },
      'cases': cases.map((c) => c.toJson()).toList(),
      'checks': checks,
    };

    File('s4-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output),
    );
    print('\nchecks: $checks');
    print('wrote s4-result.json');

    // S4 的判定在报告里做；这里只保证实验脚本本身跑通。
    expect(cases.length, greaterThanOrEqualTo(10));
  });
}

bool _digitSplit(CaseResult c) {
  for (var i = 0; i < c.lines.length - 1; i++) {
    final left = c.lines[i].trimRight();
    final right = c.lines[i + 1].trimLeft();
    if (left.isNotEmpty &&
        right.isNotEmpty &&
        RegExp(r'\d$').hasMatch(left) &&
        RegExp(r'^\d').hasMatch(right)) {
      return true;
    }
  }
  return false;
}

bool _ellipsisSplit(CaseResult c) {
  for (var i = 0; i < c.lines.length - 1; i++) {
    if (c.lines[i].endsWith('…') && c.lines[i + 1].startsWith('…')) return true;
  }
  return false;
}

bool _dashSplit(CaseResult c) {
  for (var i = 0; i < c.lines.length - 1; i++) {
    if (c.lines[i].endsWith('—') && c.lines[i + 1].startsWith('—')) return true;
  }
  return false;
}
