import 'dart:io';
import 'dart:typed_data';

import 'src/core/chinese_converter.dart';
import 'src/features/ad_clean/ad_clean.dart';
import 'src/features/chinese_convert/chinese_convert.dart';
import 'src/features/comment/comment.dart';
import 'src/features/convert_version/convert_version.dart';
import 'src/features/decrypt/decrypt.dart';
import 'src/features/encrypt/encrypt.dart';
import 'src/features/encrypt_font/encrypt_font.dart';
import 'src/features/epub_health/epub_health.dart';
import 'src/features/epub_health/epub_health_repair.dart';
import 'src/features/font_subset/font_subset.dart';
import 'src/features/footnote_to_comment/footnote_to_comment.dart';
import 'src/features/image_watermark/image_watermark.dart';
import 'src/features/img_compress/img_compress.dart';
import 'src/features/img_to_webp/img_to_webp.dart';
import 'src/features/list_font_targets/list_font_targets.dart';
import 'src/features/merge/merge.dart';
import 'src/features/navigation_editor/navigation_editor.dart';
import 'src/features/navigation_editor/navigation_model.dart';
import 'src/features/phonetic/phonetic.dart';
import 'src/features/reformat/reformat.dart';
import 'src/features/span_to_footnote/span_to_footnote.dart';
import 'src/features/split/list_split_targets.dart';
import 'src/features/split/split.dart';
import 'src/features/webp_to_img/webp_to_img.dart';
import 'src/features/yuewei/yuewei.dart';
import 'src/features/zhangyue/zhangyue.dart';

export 'src/core/chinese_converter.dart';
export 'src/features/epub_health/epub_health_report.dart';
export 'src/features/list_font_targets/list_font_targets.dart';
export 'src/features/navigation_editor/navigation_model.dart';
export 'src/features/split/list_split_targets.dart';

enum LocalToolOutput { workingCopy, export, inspection }

enum LocalEpubTool {
  epub2('转换为 EPUB 2', '转换', LocalToolOutput.workingCopy, '生成 EPUB 2 包与 NCX'),
  epub3('转换为 EPUB 3', '转换', LocalToolOutput.workingCopy, '生成 EPUB 3 包与 NAV'),
  s2t('简体转繁体', '转换', LocalToolOutput.workingCopy, 'OpenCC 词组转换，保留路径和 ID'),
  t2s('繁体转简体', '转换', LocalToolOutput.workingCopy, 'OpenCC 词组转换，保留路径和 ID'),
  health('体检与修复', '结构', LocalToolOutput.inspection, '检查编辑快照，选择安全修复项'),
  repair('应用体检修复', '结构', LocalToolOutput.workingCopy, '应用所选修复并复检'),
  navigation('目录与导航', '结构', LocalToolOutput.inspection, '编辑目录、地标和页码导航'),
  saveNavigation(
    '保存目录导航',
    '结构',
    LocalToolOutput.workingCopy,
    '同步 NAV、NCX 与特殊导航',
  ),
  validateNavigation('校验目录导航', '结构', LocalToolOutput.inspection, '校验标题和链接目标'),
  reformat('重新格式化', '结构', LocalToolOutput.workingCopy, '规范内部结构与资源引用'),
  merge('合并 EPUB', '结构', LocalToolOutput.workingCopy, '当前工作副本在前，追加其他书籍'),
  split('按章节拆分 EPUB', '结构', LocalToolOutput.export, '选择分割点，导出独立分册'),
  splitTargets('读取拆分目标', '结构', LocalToolOutput.inspection, '读取目录中的分册边界'),
  compress('压缩图片', '图片', LocalToolOutput.workingCopy, '缩减图片，较大结果保留原图'),
  toWebp('图片转 WebP', '图片', LocalToolOutput.workingCopy, '使用本地 WebP 编码组件'),
  fromWebp('WebP 转 JPEG／PNG', '图片', LocalToolOutput.workingCopy, '恢复通用格式并更新引用'),
  watermark('写入隐形水印', '图片', LocalToolOutput.workingCopy, '在支持的图片中嵌入文本水印'),
  readWatermark('读取隐形水印', '图片', LocalToolOutput.inspection, '读取支持的图片水印'),
  fontTargets('扫描字体目标', '字体', LocalToolOutput.inspection, '列出字体族与正文章节'),
  subsetFont('字体子集化', '字体', LocalToolOutput.workingCopy, 'HarfBuzz 保留所用字形与排版表'),
  encryptFont('字体加密', '字体', LocalToolOutput.workingCopy, '按原工具方式重映射字形与正文'),
  encryptNames('名称混淆', '结构', LocalToolOutput.workingCopy, '混淆资源名称并更新引用'),
  decryptNames('名称混淆解密', '结构', LocalToolOutput.workingCopy, '解开原工具支持的名称混淆'),
  cleanText('广告规则清理', '注释与正文', LocalToolOutput.workingCopy, '仅按自己输入的正则清理正文'),
  comment('批注提取', '注释与正文', LocalToolOutput.workingCopy, '按正则生成弹窗注释'),
  footnoteToComment('脚注转弹窗', '注释与正文', LocalToolOutput.workingCopy, '转换匹配的标准脚注'),
  commentToFootnote('弹窗转脚注', '注释与正文', LocalToolOutput.workingCopy, '生成标准脚注与回链'),
  yuewei('阅微转多看', '注释与正文', LocalToolOutput.workingCopy, '转换阅微注释标记'),
  zhangyue('得到／掌阅转多看', '注释与正文', LocalToolOutput.workingCopy, '转换得到或掌阅注释标记'),
  phonetic('拼音标注', '注释与正文', LocalToolOutput.workingCopy, '为全文或生僻字生成 ruby 注音');

  const LocalEpubTool(this.label, this.category, this.output, this.description);
  final String label;
  final String category;
  final LocalToolOutput output;
  final String description;

  static Iterable<LocalEpubTool> get visible => values.where(
    (tool) =>
        tool != repair &&
        tool != saveNavigation &&
        tool != splitTargets &&
        tool != validateNavigation,
  );
}

class LocalToolResult {
  const LocalToolResult(this.message, {this.files = const [], this.data});
  final String message;
  final List<String> files;
  final Object? data;
}

Future<LocalToolResult> executeLocalEpubTool(
  LocalEpubTool tool, {
  required String input,
  required String output,
  Map<String, Object?> options = const {},
  ChineseDictionary? dictionary,
  Uint8List? noteImage,
}) async {
  final inspected = await _inspect(tool, input, options);
  if (inspected != null) return inspected;
  if (tool == LocalEpubTool.split) {
    final files = <String>[];
    final message = await SplitOperation.execute(
      epubPath: input,
      outputDir: output,
      splitPoints: (options['splitPoints'] as List).cast<int>(),
      onOutput: files.add,
    );
    if (files.isEmpty) throw StateError('拆分未生成分册：$message');
    return LocalToolResult(message, files: files);
  }
  final message = await _convert(tool, input, output, options, (
    dictionary: dictionary,
    noteImage: noteImage,
  ));
  if (!await File(output).exists()) {
    if (_noChange(tool, message)) {
      return LocalToolResult('未修改工作副本：$message', files: [input]);
    }
    throw StateError('${tool.label}未生成结果：$message');
  }
  return LocalToolResult(message, files: [output]);
}

bool _noChange(LocalEpubTool tool, String message) => switch (tool) {
  LocalEpubTool.decryptNames => message == 'not_encrypted',
  LocalEpubTool.encryptNames => message == 'encrypted',
  LocalEpubTool.toWebp => message.startsWith('未找到可转换的图片'),
  LocalEpubTool.fromWebp => message.startsWith('未找到 WebP 图片'),
  _ => false,
};

Future<LocalToolResult?> _inspect(
  LocalEpubTool tool,
  String input,
  Map<String, Object?> options,
) async => switch (tool) {
  LocalEpubTool.health => LocalToolResult(
    '编辑快照体检完成',
    data: await EpubHealthInspector.scan(input),
  ),
  LocalEpubTool.navigation => LocalToolResult(
    '目录导航已读取',
    data: options['regenerate'] == true
        ? await NavigationEditorOperation.regenerateFromHeadings(input)
        : await NavigationEditorOperation.load(input),
  ),
  LocalEpubTool.fontTargets => LocalToolResult(
    await ListFontTargetsOperation.execute(epubPath: input),
    data: await ListFontTargetsOperation.scan(epubPath: input),
  ),
  LocalEpubTool.readWatermark => LocalToolResult(
    await ImageWatermarkOperation.inspect(epubPath: input),
  ),
  LocalEpubTool.splitTargets => LocalToolResult(
    '拆分目标已读取',
    data: await ListSplitTargetsOperation.execute(epubPath: input),
  ),
  LocalEpubTool.validateNavigation => LocalToolResult(
    '目录导航已校验',
    data: await NavigationEditorOperation.validate(
      input,
      (options['navigation'] as EpubNavigationDocument).sections,
    ),
  ),
  _ => null,
};

Future<String> _convert(
  LocalEpubTool tool,
  String input,
  String output,
  Map<String, Object?> options,
  ({ChineseDictionary? dictionary, Uint8List? noteImage}) resources,
) async {
  switch (tool) {
    case LocalEpubTool.epub2:
    case LocalEpubTool.epub3:
      await ConvertVersionOperation.execute(
        epubPath: input,
        outputPath: output,
        targetVersion: tool == LocalEpubTool.epub2 ? '2.0' : '3.0',
      );
      return '${tool.label}完成；已更新包版本与导航声明。';
    case LocalEpubTool.s2t:
    case LocalEpubTool.t2s:
      return ChineseConvertOperation.execute(
        epubPath: input,
        outputPath: output,
        dictionary: resources.dictionary!,
        conversion: tool == LocalEpubTool.s2t
            ? ChineseConversion.simplifiedToTraditional
            : ChineseConversion.traditionalToSimplified,
      );
    case LocalEpubTool.reformat:
      return ReformatOperation.execute(epubPath: input, outputPath: output);
    case LocalEpubTool.merge:
      return MergeOperation.execute(
        inputPaths: [input, ...(options['inputPaths'] as List).cast<String>()],
        outputPath: output,
        options: MergeOptions(
          title: options['title'] as String?,
          author: options['author'] as String?,
        ),
      );
    case LocalEpubTool.repair:
      final repaired = await EpubHealthRepairOperation.execute(
        epubPath: input,
        outputPath: output,
        selectedFixIds: (options['selectedFixIds'] as List).cast<String>(),
      );
      return repaired.toString();
    case LocalEpubTool.saveNavigation:
      final navigation = await NavigationEditorOperation.save(
        epubPath: input,
        outputPath: output,
        navigation: options['navigation'] as EpubNavigationDocument,
      );
      return navigation.toString();
    case LocalEpubTool.cleanText:
      await AdCleanOperation.execute(
        epubPath: input,
        outputPath: output,
        patterns: options['patterns'] as String,
      );
      return '广告规则清理完成；已按所选正则处理正文章节。';
    default:
      return _mediaAndNotes(tool, input, output, options, resources.noteImage);
  }
}

Future<String> _mediaAndNotes(
  LocalEpubTool tool,
  String input,
  String output,
  Map<String, Object?> options,
  Uint8List? noteImage,
) => switch (tool) {
  LocalEpubTool.compress => ImgCompressOperation.execute(
    epubPath: input,
    outputPath: output,
    jpegQuality: options['quality'] as int? ?? 82,
    pngToJpg: options['pngToJpg'] as bool? ?? false,
  ),
  LocalEpubTool.toWebp => ImgToWebpOperation.execute(
    epubPath: input,
    outputPath: output,
  ),
  LocalEpubTool.fromWebp => WebpToImgOperation.execute(
    epubPath: input,
    outputPath: output,
  ),
  LocalEpubTool.watermark => ImageWatermarkOperation.embed(
    epubPath: input,
    outputPath: output,
    watermarkText: options['watermarkText'] as String,
  ),
  LocalEpubTool.subsetFont => FontSubsetOperation.execute(
    epubPath: input,
    outputPath: output,
  ),
  LocalEpubTool.encryptFont => EncryptFontOperation.execute(
    epubPath: input,
    outputPath: output,
    targetFontFamilies: (options['fontFamilies'] as List?)?.cast<String>(),
    targetXhtmlFiles: (options['xhtmlFiles'] as List?)?.cast<String>(),
  ),
  LocalEpubTool.encryptNames => EncryptOperation.execute(
    epubPath: input,
    outputPath: output,
  ),
  LocalEpubTool.decryptNames => DecryptOperation.execute(
    epubPath: input,
    outputPath: output,
  ),
  LocalEpubTool.comment => CommentOperation.execute(
    epubPath: input,
    outputPath: output,
    regexPattern: options['pattern'] as String,
    notePngBytes: noteImage,
  ),
  LocalEpubTool.footnoteToComment => FootnoteToCommentOperation.execute(
    epubPath: input,
    outputPath: output,
    regexPattern: options['pattern'] as String,
    notePngBytes: noteImage,
  ),
  LocalEpubTool.commentToFootnote => SpanToFootnoteOperation.execute(
    epubPath: input,
    outputPath: output,
    footnoteColor: options['footnoteColor'] as String? ?? '#666666',
    noterefColor: options['noterefColor'] as String? ?? '#444444',
  ),
  LocalEpubTool.yuewei => YueweiOperation.execute(
    epubPath: input,
    outputPath: output,
    notePngBytes: noteImage,
  ),
  LocalEpubTool.zhangyue => ZhangyueOperation.execute(
    epubPath: input,
    outputPath: output,
    notePngBytes: noteImage,
  ),
  LocalEpubTool.phonetic => PhoneticOperation.execute(
    epubPath: input,
    outputPath: output,
    toneMode: options['toneMode'] as String? ?? 'mark',
    annotateAll: options['annotateAll'] as bool? ?? false,
  ),
  _ => throw ArgumentError('此工具不能作为转换执行：${tool.label}'),
};
