/// XHTML 轻量文本提取（扫描式搜索用）。
///
/// 不做完整解析：剥标签、解实体、折叠空白、块级标签转换行。相比走
/// DocumentParser + TextAggregator 的完整链路（156MB 全书约 2 秒），这条路径
/// 只关心「有没有这个词」，速度快一个量级；文本细节（空白折叠方式）可能与
/// 排版结果不同，调用方需按块级文本重新校验命中偏移。
library;

/// 块级标签：结束位置插入换行。
const Set<String> _blockTags = <String>{
  'p', 'div', 'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'li', 'ul', 'ol', 'tr', 'td', 'th', 'table', 'section', 'article',
  'blockquote', 'pre', 'figure', 'figcaption', 'hr',
};

final RegExp _dropBlocks = RegExp(
  r'<(script|style|head)\b[^>]*>[\s\S]*?</\1\s*>',
  caseSensitive: false,
);
final RegExp _tag = RegExp(r'<[^>]*>');
final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');
final RegExp _entity = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);');
final RegExp _spaces = RegExp(r'[ \t\f\u00a0]+');
final RegExp _blankLines = RegExp(r'\n{2,}');

/// 提取纯文本。
String xhtmlToPlainText(String xhtml) {
  var text = xhtml
      .replaceAll(_comment, '')
      .replaceAll(_dropBlocks, '');
  // 块级标签先替换成换行，再统一剥掉剩余标签。
  text = text.replaceAllMapped(_tag, (match) {
    final tag = match.group(0)!;
    final name = _tagName(tag);
    if (name != null && _blockTags.contains(name)) {
      return '\n';
    }
    return '';
  });
  text = text
      .replaceAllMapped(_entity, _decodeEntity)
      .replaceAll(_spaces, ' ')
      .replaceAll(_blankLines, '\n');
  return text.trim();
}

String? _tagName(String tag) {
  var start = 1;
  if (tag.length > 1 && tag[1] == '/') {
    start = 2;
  }
  final end = tag.indexOf(RegExp(r'[\s/>]'), start);
  final name = (end < 0 ? tag.substring(start) : tag.substring(start, end))
      .toLowerCase();
  return name.isEmpty ? null : name;
}

String _decodeEntity(Match match) {
  final body = match.group(1)!;
  switch (body) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
      return "'";
    case 'nbsp':
      return ' ';
    case 'mdash':
      return '—';
    case 'ndash':
      return '–';
    case 'hellip':
      return '…';
    case 'ldquo':
      return '“';
    case 'rdquo':
      return '”';
    case 'lsquo':
      return '‘';
    case 'rsquo':
      return '’';
  }
  if (body.startsWith('#x') || body.startsWith('#X')) {
    final code = int.tryParse(body.substring(2), radix: 16);
    return code == null ? match.group(0)! : String.fromCharCode(code);
  }
  if (body.startsWith('#')) {
    final code = int.tryParse(body.substring(1));
    return code == null ? match.group(0)! : String.fromCharCode(code);
  }
  return match.group(0)!;
}
