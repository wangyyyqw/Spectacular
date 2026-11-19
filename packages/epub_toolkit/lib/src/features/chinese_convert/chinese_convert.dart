import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../core/chinese_converter.dart';
import '../../core/epub_image_helper.dart';

abstract final class ChineseConvertOperation {
  static Future<String> execute({
    required String epubPath,
    required String outputPath,
    required ChineseDictionary dictionary,
    required ChineseConversion conversion,
  }) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    var count = 0;
    for (final file in archive.files.toList()) {
      if (!RegExp(
        r'\.(xhtml|html|htm|opf|ncx)$',
        caseSensitive: false,
      ).hasMatch(file.name)) {
        continue;
      }
      final original = utf8.decode(EpubImageHelper.readBytes(file));
      final document = XmlDocument.parse(original);
      var changed = false;
      for (final node in document.descendants.whereType<XmlText>().toList()) {
        if (_skip(node)) continue;
        final next = dictionary.convert(node.value);
        if (next == node.value) continue;
        node.value = next;
        changed = true;
      }
      for (final element in document.descendants.whereType<XmlElement>()) {
        for (final attribute in element.attributes) {
          if (!const {
            'alt',
            'title',
            'aria-label',
          }.contains(attribute.name.local)) {
            continue;
          }
          final next = dictionary.convert(attribute.value);
          if (next != attribute.value) {
            attribute.value = next;
            changed = true;
          }
        }
      }
      if (changed) {
        final bytes = utf8.encode(document.toXmlString());
        EpubImageHelper.addOrReplaceFile(
          archive,
          ArchiveFile.bytes(file.name, bytes),
        );
        count++;
      }
    }
    await EpubImageHelper.saveArchive(archive, outputPath);
    return '${conversion == ChineseConversion.simplifiedToTraditional ? '简体转繁体' : '繁体转简体'}：修改 $count 个文档；路径、ID 和样式声明保持不变。';
  }

  static bool _skip(XmlText node) {
    for (final ancestor in node.ancestors.whereType<XmlElement>()) {
      if (const {
        'script',
        'style',
        'code',
        'pre',
        'identifier',
      }.contains(ancestor.name.local)) {
        return true;
      }
    }
    return false;
  }
}
