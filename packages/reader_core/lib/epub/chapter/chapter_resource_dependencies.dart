import '../../css/parser.dart';
import '../../parser/document_parser.dart';

/// 只收集排版资源，不把普通超链接当图片；脚注依赖沿用正式解析结果。
List<String> chapterAssetReferences(ParsedDocument document) {
  final result = <String>[];
  final pending = <ParsedElement>[document.root];
  result.addAll(cssResourceUrls(document.htmlAttributes['style'] ?? ''));
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    final attributes = node.attributes;
    if (const {
      'img',
      'image',
      'object',
      'video',
      'audio',
      'source',
    }.contains(node.tag)) {
      for (final name in ['src', 'href', 'xlink:href', 'data', 'poster']) {
        if (attributes[name] case final value?) result.add(value);
      }
    }
    result.addAll(cssResourceUrls(attributes['style'] ?? ''));
    pending.addAll(node.children.whereType<ParsedElement>());
  }
  return result;
}

Iterable<String> stylesheetAssetReferences(CssStylesheet sheet) sync* {
  for (final rule in sheet.rules) {
    for (final declaration in rule.declarations) {
      yield* cssResourceUrls(declaration.value);
    }
  }
  for (final face in sheet.fontFaces) {
    for (final source in face.sources) {
      if (!source.isLocal) yield source.ref;
    }
  }
}

final _url = RegExp(
  r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*?))\s*\)''',
  caseSensitive: false,
);

Iterable<String> cssResourceUrls(String text) sync* {
  for (final match in _url.allMatches(text)) {
    yield (match[1] ?? match[2] ?? match[3]!).trim();
  }
}
