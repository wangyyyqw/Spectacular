import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/text/font_coverage.dart';

const _regularPath = '../../test_fonts/SourceHanSerifSC-Regular.otf';

/// 构造最小 sfnt：仅一个 cmap 子表（format 12，覆盖 U+20000..U+20001）。
Uint8List _buildFormat12Font() {
  final buffer = BytesBuilder();
  final header = ByteData(12)
    ..setUint32(0, 0x00010000) // sfntVersion
    ..setUint16(4, 1) // numTables
    ..setUint16(6, 0) // searchRange/entrySelector/rangeShift 随意
    ..setUint16(8, 0)
    ..setUint16(10, 0);
  buffer.add(header.buffer.asUint8List());
  // 表记录：'cmap'，offset 28（12 + 16）。
  final record = ByteData(16)
    ..setUint32(0, 0x636D6170) // 'cmap'
    ..setUint32(8, 28);
  buffer.add(record.buffer.asUint8List());
  // cmap：version 0，1 个子表（platform 3, encoding 10, offset 12）。
  final cmap = ByteData(12)
    ..setUint16(0, 0)
    ..setUint16(2, 1)
    ..setUint16(4, 3)
    ..setUint16(6, 10)
    ..setUint32(8, 12);
  buffer.add(cmap.buffer.asUint8List());
  // format 12：format/reserved/length/language/nGroups + 1 组。
  final subtable = ByteData(16 + 12)
    ..setUint16(0, 12)
    ..setUint16(2, 0)
    ..setUint32(4, 28)
    ..setUint32(8, 0)
    ..setUint32(12, 1)
    ..setUint32(16, 0x20000)
    ..setUint32(20, 0x20001)
    ..setUint32(24, 1);
  buffer.add(subtable.buffer.asUint8List());
  return buffer.toBytes();
}

/// 构造最小 sfnt：format 4 中 A..C 映射到 glyph 0..2，用于验证
/// `.notdef` 不会被误判为可用字形。
Uint8List _buildFormat4Font() {
  final buffer = BytesBuilder();
  final header = ByteData(12)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, 1);
  buffer.add(header.buffer.asUint8List());
  final record = ByteData(16)
    ..setUint32(0, 0x636D6170)
    ..setUint32(8, 28);
  buffer.add(record.buffer.asUint8List());
  final cmap = ByteData(12)
    ..setUint16(2, 1)
    ..setUint16(4, 3)
    ..setUint16(6, 1)
    ..setUint32(8, 12);
  buffer.add(cmap.buffer.asUint8List());
  final subtable = ByteData(32)
    ..setUint16(0, 4)
    ..setUint16(2, 32)
    ..setUint16(6, 4)
    ..setUint16(8, 4)
    ..setUint16(10, 1)
    ..setUint16(12, 0)
    // endCode: A..C、0xFFFF 哨兵。
    ..setUint16(14, 0x43)
    ..setUint16(16, 0xFFFF)
    // reservedPad + startCode。
    ..setUint16(20, 0x41)
    ..setUint16(22, 0xFFFF)
    // idDelta：A 映射到 glyph 0，B/C 映射到 1/2；哨兵 delta 1。
    ..setUint16(24, (0 - 0x41) & 0xFFFF)
    ..setUint16(26, 1)
    // idRangeOffset 全 0，走 idDelta 直接映射。
    ..setUint16(28, 0)
    ..setUint16(30, 0);
  buffer.add(subtable.buffer.asUint8List());
  return buffer.toBytes();
}

void main() {
  group('FontCoverage cmap 解析', () {
    test('真实字体：常用字覆盖、PUA 缺失、清单导出', () async {
      final bytes = await File(_regularPath).readAsBytes();
      final coverage = FontCoverage.parse(Uint8List.fromList(bytes));
      expect(coverage, isNotNull);
      expect(coverage!.covers(0x4E2D), isTrue, reason: '中');
      expect(coverage.covers(0x41), isTrue, reason: 'A');
      expect(coverage.covers(0xE000), isFalse, reason: '私用区不覆盖');
      final missing = coverage.missingCodePoints('中A\uE000\uE001');
      expect(missing, [0xE000, 0xE001]);
      final report = coverage.exportMissingReport('中\uE000');
      expect(report, 'U+E000 [\uE000]');
    });

    test('合成 format 12：增补平面码点覆盖', () {
      final coverage = FontCoverage.parse(_buildFormat12Font());
      expect(coverage, isNotNull);
      expect(coverage!.covers(0x20000), isTrue);
      expect(coverage.covers(0x20001), isTrue);
      expect(coverage.covers(0x20002), isFalse);
      expect(coverage.covers(0x4E2D), isFalse, reason: '无 format 4 子表');
    });

    test('合成 format 4：映射到 glyph 0 的码点视为缺字', () {
      final coverage = FontCoverage.parse(_buildFormat4Font());
      expect(coverage, isNotNull);
      expect(coverage!.covers(0x41), isFalse, reason: '.notdef 不可渲染');
      expect(coverage.covers(0x42), isTrue);
      expect(coverage.covers(0x43), isTrue);
      expect(coverage.covers(0x44), isFalse);
    });

    test('坏字节/截断/TTC 返回 null 不抛异常', () {
      expect(FontCoverage.parse(Uint8List.fromList(<int>[1, 2, 3])), isNull);
      expect(FontCoverage.parse(Uint8List(0)), isNull);
      final ttc = ByteData(12)..setUint32(0, 0x74746366); // 'ttcf'
      expect(FontCoverage.parse(ttc.buffer.asUint8List()), isNull);
      final real = File(_regularPath).readAsBytesSync();
      expect(
        FontCoverage.parse(Uint8List.sublistView(real, 0, 100)),
        isNull,
        reason: 'cmap 表体超出截断范围：不可读即返回 null（§28.4 只记格式校验）',
      );
    });
  });

  group('BookFontLoader.coverage 集成', () {
    test('注册后可查覆盖；未注册返回 null', () async {
      final loader = BookFontLoader(bookId: 'c1');
      expect(loader.coverage('songti'), isNull);
      final faces = CssParser.parse(
        '@font-face { font-family: songti; src: url("$_regularPath"); }',
      ).fontFaces;
      await loader.load(faces, resolveBytes: (url) => File(url).readAsBytes());
      final coverage = loader.coverage('songti');
      expect(coverage, isNotNull);
      expect(coverage!.missingCodePoints('中文'), isEmpty);
    });
  });

  group('默认回退链接线（P3-04，§68.4）', () {
    test('声明 fallback 之后追加默认 CJK 链，主族不重复', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': '宋体, 黑体',
      });
      final textStyle = TextLayoutEngine.textStyleFor(style);
      expect(textStyle.fontFamily, FontFamilyAliases.song);
      expect(textStyle.fontFamilyFallback, [
        FontFamilyAliases.hei,
        'Noto Serif CJK SC',
        'Noto Sans CJK SC',
      ]);
    });

    test('黑体主族不回落内置宋体（P9-05）', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': '黑体',
      });
      final textStyle = TextLayoutEngine.textStyleFor(style);
      expect(textStyle.fontFamily, FontFamilyAliases.hei);
      expect(
        textStyle.fontFamilyFallback,
        isNot(contains(FontFamilyAliases.song)),
        reason: '黑体书不能因为内置宋体而整体变宋体',
      );
      expect(textStyle.fontFamilyFallback, contains('PingFang SC'));
    });

    test('无声明族也带默认链（缺字兜底）', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
      });
      final textStyle = TextLayoutEngine.textStyleFor(style);
      expect(textStyle.fontFamilyFallback, FontFamilyAliases.defaultChain);
    });

    test('生僻字文本走回退链渲染不崩溃且出墨', () async {
      final loader = BookFontLoader(bookId: 'rare');
      final faces = CssParser.parse(
        '@font-face { font-family: serif; src: url("$_regularPath"); }',
      ).fontFaces;
      await loader.load(faces, resolveBytes: (url) => File(url).readAsBytes());
      final style = ComputedStyle(<String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': loader.engineFamily('serif')!,
      });
      final layout = TextLayoutEngine.layout(
        text: '常见字龘𠀀混排',
        style: style,
        maxWidth: 200,
      );
      expect(layout.lineCount, greaterThan(0));
      expect(layout.height, greaterThan(0));
    });
  });
}
