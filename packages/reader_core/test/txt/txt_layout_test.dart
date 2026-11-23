import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_core/txt.dart';

const _paragraph =
    '正文，，首行应当由样式缩进两个字，原文件中的空格不能再重复占位。'
    '后续文字需要在正式阅读引擎中两端对齐，改变字号后缩进同步更新。';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('txt-layout-song');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            '../../apps/reader_mobile/assets/fonts/MoyuSerif-Regular.otf',
          ).readAsBytes(),
        ),
      ),
    );
    await loader.load();
  });

  test('TXT生成的卷章居中，正文首行2em缩进、两端对齐且连续标点压缩', () async {
    final temporary = await Directory.systemTemp.createTemp('txt-layout-');
    addTearDown(() => temporary.delete(recursive: true));
    final target = File('${temporary.path}/layout.epub');
    await TxtEpubConverter.convertBytes(
      Uint8List.fromList(
        utf8.encode('　 \t第一卷 春天\n\t　第一章 开始\n  \t　$_paragraph'),
      ),
      target,
    );
    const width = 366.6666666666667;
    final source = await const EpubFormatOpener().openFile(
      target,
      options: const ReaderOpenOptions(
        contentWidth: width,
        contentHeight: 773.1694444444445,
      ),
    );
    addTearDown(source.close);
    for (final fontSize in [21.0, 25.0]) {
      await source.applyOverrides(
        ReaderOverrides(
          fontSize: fontSize,
          lineHeight: 1.6,
          fontFamily: 'txt-layout-song',
        ),
      );
      final volume = (await source.loadChapter(0)).single;
      final chapter = (await source.loadChapter(1)).single;
      for (final page in [volume, chapter]) {
        final heading = page.slices.first.block;
        expect(heading.style!.whiteSpace.name, 'normal');
        expect(heading.style!.textAlign.name, 'center');
        expect(heading.style!.textIndent, 0);
        expect(heading.layout.lines.first.indent, 0);
        expect(
          TextHitTester.lineBoxes(page).first.rect.center.dx,
          closeTo(width / 2, .01),
        );
      }
      final paragraph = chapter.slices.last.block;
      expect(paragraph.layout.text, _paragraph);
      expect(paragraph.style!.whiteSpace.name, 'normal');
      expect(paragraph.style!.textAlign.name, 'justify');
      expect(paragraph.style!.textSpacingTrim.name, 'trimAll');
      expect(paragraph.style!.textIndent, closeTo(fontSize * 2, .01));
      expect(paragraph.layout.lines.first.indent, closeTo(fontSize * 2, .01));
      expect(paragraph.layout.lines[1].indent, 0);
      expect(paragraph.layout.lines.first.justifyExtra, greaterThan(0));
      final spacing = paragraph.layout.lines.first.spacing!;
      for (final offset in [2, 3]) {
        expect(spacing.glyphs[offset]!.reduction, closeTo(fontSize * .4, .05));
      }
      final lines = TextHitTester.lineBoxes(chapter)
          .where((line) => identical(line.slice.block, paragraph))
          .toList();
      expect(
        lines.first.rect.left - lines[1].rect.left,
        closeTo(fontSize * 2, .01),
      );
    }
  });
}
