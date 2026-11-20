import 'txt_models.dart';

const chapterNumberCharacters = '0-9０-９零〇一二两兩三四五六七八九十百千万亿壹贰貳叁參肆伍陆陸柒捌玖拾佰仟萬億廿卅卌';
const _number = '[$chapterNumberCharacters]{1,16}';
const _space = r'[ \t　]{0,8}';
const _opening = r'[【\[（(「『]?';
const _ending = r'[^\r\n]{0,60}';
const _chapter =
    '$_opening$_space'
    '第$_space$_number$_space'
    '(?:章|节(?!课)|節(?!課)|回(?![合来來事去])|话|話|幕|期)$_ending';
const _volume =
    '$_opening$_space(?:第$_space$_number$_space'
    '(?:卷|部(?![分赛賽游])|册|冊|集(?![合和])|辑|輯|季)'
    '|[卷册冊]$_space$_number)$_ending';
const _special =
    r'[【\[（(「『]?(?:序章|序言|前言|引子|楔子|序幕|终章|終章|'
    r'后记|後記|尾声|尾聲|番外(?:篇)?|最终章|最終章|大结局|大結局)'
    r'(?:$|[ \t　:：·、—_\-】\]）)」』].{0,50})';

/// 强标题默认参与自动识别；宽松规则只在有编号序列证据时采用。
const builtInChapterRules = <ChapterRule>[
  ChapterRule(
    id: 'builtin-volume-chapter',
    name: '卷号与章号同一行',
    pattern:
        '$_opening$_space'
        '第?$_space$_number$_space[卷部册冊集]'
        '[^\r\n]{0,20}第?$_space$_number$_space[章回节節话話]$_ending',
    autoEnabled: true,
  ),
  ChapterRule(
    id: 'builtin-chinese',
    name: '中文章回',
    pattern: _chapter,
    volumePattern: _volume,
    autoEnabled: true,
  ),
  ChapterRule(
    id: 'builtin-english',
    name: 'Chapter / Section / Episode',
    pattern:
        r'(?:Chapter|Section|Episode)[ \t　]+(?:[0-9０-９]{1,8}|[IVXLCDM]{1,12})'
        r'(?:$|[ \t　:：.、\-].{0,60})',
    volumePattern:
        r'(?:Part|Book)[ \t　]+(?:[0-9０-９]{1,8}|[IVXLCDM]{1,12})'
        r'(?:$|[ \t　:：.、\-].{0,60})',
    caseSensitive: false,
    autoEnabled: true,
  ),
  ChapterRule(
    id: 'builtin-special',
    name: '序章、前言与番外',
    pattern: _special,
    autoEnabled: true,
  ),
  ChapterRule(
    id: 'builtin-unnamed',
    name: '未命名章节（需前后章号佐证）',
    pattern: r'未命名(?:草稿|章节|章節)',
    autoEnabled: true,
  ),
  ChapterRule(
    id: 'builtin-numbered',
    name: '数字、分隔符与标题',
    pattern:
        '$_number(?:[、，,:：_—.．-]|[ \t　]+)'
        '[^\r\n]{1,60}',
    autoEnabled: true,
  ),
  ChapterRule(
    id: 'builtin-bracket-number',
    name: '括号数字与标题',
    pattern: '[【\\[（(]$_number[】\\]）)][^\r\n]{0,60}',
    autoEnabled: true,
  ),
  ChapterRule(id: 'builtin-number-only', name: '纯数字标题', pattern: _number),
  ChapterRule(
    id: 'builtin-symbol',
    name: '星号或分隔线标题',
    pattern: r'(?:[☆★✦✧][^\r\n]{1,60}|={3,6}[^=\r\n]{1,60}={3,6})',
  ),
  ChapterRule(
    id: 'builtin-short-line',
    name: '顶格短行（手动）',
    pattern: r'\S[^\r\n]{0,29}',
  ),
];
