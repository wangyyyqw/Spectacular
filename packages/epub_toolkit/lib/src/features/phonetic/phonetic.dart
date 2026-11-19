import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:pinyin/pinyin.dart';

import '../../core/epub_packer.dart';
import 'common_chars.dart';

class PhoneticOperation {
  PhoneticOperation._();

  static const toneModeMark = 'mark';
  static const toneModeNone = 'none';
  static const toneModeNumber = 'number';

  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    String toneMode = toneModeMark,
    bool annotateAll = true,
  }) async {
    final archive = ZipDecoder().decodeBytes(
      await File(epubPath).readAsBytes(),
    );
    final log = StringBuffer()
      ..writeln('开始拼音标注...')
      ..writeln('声调模式: ${_toneModeName(toneMode)}')
      ..writeln('标注范围: ${annotateAll ? "全文注音" : "仅生僻字"}');
    final (fileCount, annotateCount, charCount, failCount) = _annotateArchive(
      archive,
      _parseFormat(toneMode),
      annotateAll,
      log,
    );
    await EpubPacker.pack(archive: archive, outputPath: outputPath);
    log
      ..writeln(
        '\n拼音标注完成: 处理 $fileCount 个 HTML 文件, '
        '$annotateCount 个文件有标注, 共标注 $charCount 个字符'
        '${failCount > 0 ? '，$failCount 个文件失败' : ''}',
      )
      ..writeln('输出文件: $outputPath');
    return log.toString();
  }

  static PinyinFormat _parseFormat(String toneMode) => switch (toneMode) {
    toneModeMark => PinyinFormat.WITH_TONE_MARK,
    toneModeNumber => PinyinFormat.WITH_TONE_NUMBER,
    _ => PinyinFormat.WITHOUT_TONE,
  };

  static String _toneModeName(String toneMode) => switch (toneMode) {
    toneModeMark => '带音标',
    toneModeNumber => '数字声调',
    _ => '不带声调',
  };

  static (int, int, int, int) _annotateArchive(
    Archive archive,
    PinyinFormat format,
    bool annotateAll,
    StringBuffer log,
  ) {
    var fileCount = 0;
    var annotateCount = 0;
    var charCount = 0;
    var failCount = 0;
    for (final file in archive.files.toList()) {
      final name = file.name.toLowerCase();
      if (!file.isFile ||
          !const ['.xhtml', '.html', '.htm'].any(name.endsWith)) {
        continue;
      }
      fileCount++;
      try {
        final (content, count) = _annotateHtml(
          utf8.decode(file.content),
          format,
          annotateAll,
        );
        if (count == 0) continue;
        archive.addFile(ArchiveFile.string(file.name, content));
        annotateCount++;
        charCount += count;
      } on FormatException catch (error) {
        failCount++;
        log.writeln('  文件 ${file.name} 标注失败: $error');
      }
    }
    return (fileCount, annotateCount, charCount, failCount);
  }

  static final _htmlTokens = RegExp(
    r'''<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<!DOCTYPE\b(?:[^>"'\[]|"[^"]*"|'[^']*'|\[[\s\S]*?\])*>|</?[A-Za-z][\w:.-]*(?:[^<>"']|"[^"]*"|'[^']*')*>|[^<]+|<''',
    caseSensitive: false,
  );
  static final _tagName = RegExp(r'^<(/?)([A-Za-z][\w:.-]*)');
  static final _textParts = RegExp(r'&[^\s<&;]+;|[^&]+|&');
  static const _protectedNames = {
    'head',
    'title',
    'script',
    'style',
    'pre',
    'code',
    'ruby',
    'rt',
    'rp',
    'textarea',
  };
  static final _commonRunes = kCommonHanzi.runes.toSet();

  static (String, int) _annotateHtml(
    String content,
    PinyinFormat format,
    bool annotateAll,
  ) {
    final output = StringBuffer();
    final protected = <String>[];
    var charCount = 0;
    for (final match in _htmlTokens.allMatches(content)) {
      final token = match.group(0)!;
      if (token.startsWith('<')) {
        output.write(token);
        _updateProtectedElements(token, protected);
      } else if (protected.isNotEmpty) {
        output.write(token);
      } else {
        final (annotated, count) = _annotateText(token, format, annotateAll);
        output.write(annotated);
        charCount += count;
      }
    }
    return (output.toString(), charCount);
  }

  static void _updateProtectedElements(String token, List<String> protected) {
    final tag = _tagName.firstMatch(token);
    if (tag == null) return;
    final name = tag.group(2)!.split(':').last.toLowerCase();
    if (protected.isNotEmpty &&
        const {'script', 'style'}.contains(protected.last) &&
        name != protected.last) {
      return;
    }
    if (tag.group(1) == '/') {
      final index = protected.lastIndexOf(name);
      if (index >= 0) protected.removeRange(index, protected.length);
    } else if (_protectedNames.contains(name) && !token.endsWith('/>')) {
      protected.add(name);
    }
  }

  static (String, int) _annotateText(
    String text,
    PinyinFormat format,
    bool annotateAll,
  ) {
    final output = StringBuffer();
    var count = 0;
    for (final match in _textParts.allMatches(text)) {
      final part = match.group(0)!;
      if (part.startsWith('&') && part.endsWith(';')) {
        output.write(part);
        continue;
      }
      for (final rune in part.runes) {
        final character = String.fromCharCode(rune);
        if (!_isChinese(rune) ||
            (!annotateAll && _commonRunes.contains(rune))) {
          output.write(character);
          continue;
        }
        final List<String> pronunciations;
        try {
          pronunciations = PinyinHelper.convertToPinyinArray(character, format);
        } on RangeError {
          output.write(character);
          continue;
        }
        if (pronunciations.isEmpty || pronunciations.first == character) {
          output.write(character);
          continue;
        }
        output.write('<ruby>$character<rt>${pronunciations.first}</rt></ruby>');
        count++;
      }
    }
    return (output.toString(), count);
  }

  static bool _isChinese(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3400 && rune <= 0x4DBF);
}
