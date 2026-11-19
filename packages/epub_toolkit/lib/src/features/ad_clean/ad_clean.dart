import 'dart:convert';

import 'package:archive/archive.dart';

import '../../core/epub_image_helper.dart';

/// EPUB 广告清理操作
///
/// 根据用户提供的正则表达式规则，批量清理 EPUB 中所有 HTML 文件内的广告内容，
/// 并将清理后的 EPUB 保存到指定路径。
class AdCleanOperation {
  AdCleanOperation._();

  /// 按正则规则清理 EPUB 中的广告
  ///
  /// 参数 [epubPath] 原始 EPUB 文件路径
  /// 参数 [outputPath] 输出 EPUB 文件路径
  /// 参数 [patterns] 规则字符串，格式为 'pattern1|||replacement1|||pattern2|||replacement2'
  ///   奇数位（第 1、3、5... 段）为正则表达式，偶数位（第 2、4、6... 段）为替换文本
  static Future<void> execute({
    required String epubPath,
    required String outputPath,
    required String patterns,
  }) async {
    // 解析规则字符串为正则-替换对列表
    final rules = _parsePatterns(patterns);
    if (rules.isEmpty) {
      throw ArgumentError('patterns 格式无效，未解析到有效的清理规则');
    }

    final archive = await EpubImageHelper.readArchive(epubPath);
    final htmlFiles = archive.files.where((file) {
      final name = file.name.toLowerCase();
      return file.isFile &&
          (name.endsWith('.xhtml') ||
              name.endsWith('.html') ||
              name.endsWith('.htm'));
    }).toList();
    for (final file in htmlFiles) {
      var content = utf8.decode(file.content, allowMalformed: true);
      for (final rule in rules) {
        content = content.replaceAll(rule.pattern, rule.replacement);
      }
      EpubImageHelper.addOrReplaceFile(
        archive,
        ArchiveFile.string(file.name, content),
      );
    }
    await EpubImageHelper.saveArchive(archive, outputPath);
  }

  /// 解析 patterns 字符串为正则-替换规则列表
  ///
  /// 参数 [patterns] 用 ||| 分隔的规则字符串
  /// 返回解析后的规则列表；正则编译失败时抛出 FormatException
  static List<_ReplaceRule> _parsePatterns(String patterns) {
    final parts = patterns.split('|||');
    final rules = <_ReplaceRule>[];

    // 每两个相邻段组成一条规则：第一段为正则，第二段为替换文本
    for (var i = 0; i + 1 < parts.length; i += 2) {
      final patternStr = parts[i];
      final replacement = parts[i + 1];
      if (patternStr.isEmpty) continue;
      try {
        rules.add(_ReplaceRule(RegExp(patternStr), replacement));
      } catch (e) {
        // 正则表达式语法错误时抛出异常，提示用户修正
        throw FormatException('正则表达式无效 "$patternStr": $e');
      }
    }
    return rules;
  }
}

/// 正则替换规则（内部使用）
class _ReplaceRule {
  _ReplaceRule(this.pattern, this.replacement);

  /// 要匹配的正则表达式
  final RegExp pattern;

  /// 匹配内容的替换文本
  final String replacement;
}
