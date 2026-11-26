import 'package:reader_core/editing/epub_editing.dart';

/// 样式只包含排版声明，不改正文、标签、链接或作者的 class。
class BookStylePreset {
  const BookStylePreset(
    this.id,
    this.name,
    this.category,
    this.description,
    this.declarations, {
    this.sample = '文字与留白相互照应，让每一段阅读都有自然的节奏。翻过这一页，故事仍在继续。',
  });

  final String id, name, category, description, sample;
  final Map<String, String> declarations;

  String get css => declarations.entries
      .map((entry) => '${entry.key}: ${entry.value};')
      .join('\n');
}

const bookStylePresets = [
  BookStylePreset('body-indent', '首行缩进正文', '正文', '两端对齐，首行缩进两字，适合连续阅读。', {
    'text-indent': '2em',
    'text-align': 'justify',
    'line-height': '1.8',
    'margin-top': '0',
    'margin-bottom': '0.6em',
  }),
  BookStylePreset('body-flat', '无缩进正文', '正文', '用段间距区分段落，适合说明与短篇内容。', {
    'text-indent': '0',
    'text-align': 'justify',
    'line-height': '1.7',
    'margin-top': '0',
    'margin-bottom': '0.9em',
  }),
  BookStylePreset('body-compact', '紧凑正文', '正文', '缩小行距与段距，适合信息密集的正文。', {
    'text-indent': '2em',
    'text-align': 'justify',
    'line-height': '1.5',
    'margin-top': '0',
    'margin-bottom': '0.35em',
  }),
  BookStylePreset('title-chapter', '居中章标题', '标题', '放大、加粗并居中；标题后尽量不分页。', {
    'font-size': '1.6em',
    'font-weight': 'bold',
    'text-align': 'center',
    'text-indent': '0',
    'line-height': '1.4',
    'margin-top': '1.5em',
    'margin-bottom': '1em',
    'page-break-after': 'avoid',
  }, sample: '第一章  山水之间'),
  BookStylePreset('title-section', '左对齐小标题', '标题', '清楚区分章节层级，保留紧凑的阅读节奏。', {
    'font-size': '1.2em',
    'font-weight': 'bold',
    'text-align': 'left',
    'text-indent': '0',
    'line-height': '1.5',
    'margin-top': '1.2em',
    'margin-bottom': '0.6em',
    'page-break-after': 'avoid',
  }, sample: '一、沿着河流出发'),
  BookStylePreset('title-subtitle', '轻量副标题', '标题', '常规字重与疏朗字距，适合章名下的副题。', {
    'font-size': '1.05em',
    'font-weight': 'normal',
    'text-align': 'center',
    'text-indent': '0',
    'letter-spacing': '0.12em',
    'line-height': '1.5',
    'margin-top': '0.5em',
    'margin-bottom': '1.2em',
  }, sample: '在日常里发现细微的美'),
  BookStylePreset('quote-inset', '缩进引文', '引用与提示', '左右留白并收小字号，适合独立引用。', {
    'font-size': '0.95em',
    'text-indent': '0',
    'text-align': 'left',
    'line-height': '1.7',
    'margin': '1em 1.5em',
  }, sample: '“书籍的意义，在于让一个人的经验，成为许多人心中的回声。”'),
  BookStylePreset('quote-rule', '侧线引文', '引用与提示', '细竖线与内边距强调引文，颜色跟随正文。', {
    'text-indent': '0',
    'text-align': 'left',
    'line-height': '1.7',
    'margin': '1em 0',
    'padding-left': '1em',
    'border-left': '0.15em solid currentColor',
  }, sample: '阅读留下的，不只是故事，还有重新观察世界的角度。'),
  BookStylePreset('note-box', '边框提示', '引用与提示', '细线围合提示内容，不固定背景或文字颜色。', {
    'text-indent': '0',
    'text-align': 'left',
    'line-height': '1.6',
    'margin': '1em 0',
    'padding': '0.8em',
    'border': '1px solid currentColor',
    'border-radius': '0.25em',
  }, sample: '阅读提示：此处的注释帮助理解上下文，可在读完本节后回看。'),
  BookStylePreset('caption', '居中图注', '辅助文字', '较小字号与居中排列，适合图片说明。', {
    'font-size': '0.85em',
    'text-align': 'center',
    'text-indent': '0',
    'line-height': '1.5',
    'margin-top': '0.5em',
    'margin-bottom': '1em',
  }, sample: '图 1  清晨的山间小径'),
  BookStylePreset('footnote', '注释正文', '辅助文字', '较小字号与紧凑段距，不改变注释标记和回链。', {
    'font-size': '0.85em',
    'text-align': 'left',
    'text-indent': '0',
    'line-height': '1.5',
    'margin-top': '0.4em',
    'margin-bottom': '0.4em',
  }, sample: '[1] 这里补充原文涉及的背景资料与出处。'),
  BookStylePreset('signature', '右对齐落款', '辅助文字', '用于作者署名、日期与短小的段末说明。', {
    'font-size': '0.9em',
    'text-align': 'right',
    'text-indent': '0',
    'line-height': '1.5',
    'margin-top': '0.8em',
    'margin-bottom': '0.5em',
  }, sample: '作者记于初秋'),
];

/// 追加标准行内声明，保留原始 CSS（含未知属性和带分号的 URL）。
/// 作者的 !important 默认保留；用户显式选择覆盖时才提高优先级。
void applyBookStyleToElement(
  EpubEditSession session,
  EditableElementRef target,
  BookStylePreset preset, {
  bool important = false,
}) {
  session.checkElement(target);
  if (!isBookStyleTarget(target)) {
    throw const EpubEditException('请选择 body 中的正文元素后应用样式');
  }
  final original = target.attributes['style']?.trimRight() ?? '';
  final declarations = preset.declarations.entries
      .map(
        (entry) =>
            '${entry.key}: ${entry.value}${important ? ' !important' : ''};',
      )
      .join(' ');
  if (original.endsWith(declarations)) return;
  final value =
      '${original.isEmpty ? '' : '$original${original.endsWith(';') ? '' : ';'} '}$declarations';
  session.transaction(
    '应用样式：${preset.name}',
    (tx) => tx.writeText(target.path, target.replaceAttribute('style', value)),
  );
}

bool isBookStyleTarget(EditableElementRef target) =>
    !{'script', 'style'}.contains(target.tag) &&
    (target.tag == 'body' ||
        target.ancestors.any((node) => node.tag == 'body'));
