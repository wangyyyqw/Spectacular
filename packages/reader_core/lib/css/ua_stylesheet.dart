import 'cascade.dart';
import 'computed_style.dart';
import 'parser.dart';

/// UA 默认样式表（P7-03）。
///
/// 规则文本按 WHATWG HTML 15.3（渲染建议）分节，每条注明规范出处；
/// 差异取舍对照 Reeden 2.0.0 的 134 规则 UA 表（`参考/reeden/reports/
/// 630-ua-stylesheet.md`）与技术方案 §73。两条读取路径：
///
/// 1. [uaRules]：喂给 `Cascade.compute` 的完整规则集（UA origin，供
///    作者样式接入后的逐元素层叠使用）；
/// 2. [UaBlockDefaults]：当前「单一基准样式」管线可直接消费的块级
///    覆盖层（仅含当前排版/绘制栈已消费的物理属性）。
const String uaStylesheetCss = '''
/* ==== 隐藏元素（WHATWG HTML 15.3.1；P8-03 对标 Reeden 630）==== */
/* 解析器按脚本可用把 noscript 解析成原始文本，样式须与 DOM 层一致；
   与 Chrome 行为一致（Reeden 630 号 §2 差异 1）。 */
noscript { display: none !important; }
area, base, basefont, datalist, head, link, meta, noembed, noframes,
param, rp, script, style, template, title { display: none; }
[hidden] { display: none; }
input[type=hidden] { display: none; }
dialog:not([open]) { display: none; }

/* ==== 页面（15.3.2；边距由阅读器设置接管，Reeden 630 号 §4-3）==== */
html, body { display: block; }
body { margin: 0; }

/* ==== 排版前注入（P7-25；对照 Reeden 必配注入样式，630 号 §4-3）====
   html/body 基础约束 + body 建立 BFC（flow-root）：阻断作者页面的
   裸 float/负 margin 污染整章。 */
html, body { overflow: hidden; min-height: 0; height: auto; }
body { display: flow-root; }

/* ==== 流内容（15.3.3）==== */
p { margin-top: 1em; margin-bottom: 1em; }
blockquote, figure, listing, plaintext, pre, xmp {
  margin-top: 1em; margin-bottom: 1em;
}
blockquote, figure { margin-left: 40px; margin-right: 40px; }
address { font-style: italic; }
pre { white-space: pre; }

/* ==== 表现属性（15.3.3 表；P8-03 属性选择器落地）==== */
p[align=left], div[align=left], h1[align=left], h2[align=left],
h3[align=left], h4[align=left], h5[align=left], h6[align=left],
table[align=left] { text-align: left; }
p[align=center], div[align=center], h1[align=center], h2[align=center],
h3[align=center], h4[align=center], h5[align=center], h6[align=center],
table[align=center] { text-align: center; }
p[align=right], div[align=right], h1[align=right], h2[align=right],
h3[align=right], h4[align=right], h5[align=right], h6[align=right],
table[align=right] { text-align: right; }
center { text-align: center; }

/* ==== 分节与标题（15.3.6）==== */
/* 字号 2.00/1.50/1.17/1.00/0.83/0.67em、上下边距 0.67/0.83/1.00/
   1.33/1.67/2.33em 取自 WHATWG 渲染建议；
   标题避开页底（break-after: avoid）采纳自 Reeden（architecture 6.3，
   630 号 §2 差异 5）。 */
h1 { font-size: 2em; font-weight: bold; margin-top: 0.67em; margin-bottom: 0.67em; page-break-after: avoid; }
h2 { font-size: 1.5em; font-weight: bold; margin-top: 0.83em; margin-bottom: 0.83em; page-break-after: avoid; }
h3 { font-size: 1.17em; font-weight: bold; margin-top: 1em; margin-bottom: 1em; page-break-after: avoid; }
h4 { font-size: 1em; font-weight: bold; margin-top: 1.33em; margin-bottom: 1.33em; page-break-after: avoid; }
h5 { font-size: 0.83em; font-weight: bold; margin-top: 1.67em; margin-bottom: 1.67em; page-break-after: avoid; }
h6 { font-size: 0.67em; font-weight: bold; margin-top: 2.33em; margin-bottom: 2.33em; page-break-after: avoid; }
hgroup > p { margin-top: 1em; margin-bottom: 1em; }

/* ==== 列表（15.3.7；嵌套类型 disc→circle→square，CSS Lists 3 §4.3）==== */
li { display: list-item; }
/* 刻意差异（flat 管线近似）：WHATWG li 默认 margin 0、缩进来自
   ul 的 padding；flat 无嵌套盒子，li 自带 40px 左边距承担缩进
   （P3-23 标记 gutter 语义），与旧 UaBlockDefaults 一致。 */
li { margin-left: 40px; }
ul ul, ul ol, ol ul, ol ol { margin-top: 0; margin-bottom: 0; }
ul, ol { margin-top: 1em; margin-bottom: 1em; padding-left: 40px; }
dl { margin-top: 1em; margin-bottom: 1em; }
dd { margin-left: 40px; }
dd + dt, dt + dt { margin-top: 0.5em; }
dt { font-weight: bold; }
ul { list-style-type: disc; }
ol { list-style-type: decimal; }
ul[type=none], ol[type=none] { list-style-type: none; }
ul[type=disc] { list-style-type: disc; }
ul[type=circle] { list-style-type: circle; }
ul[type=square] { list-style-type: square; }
ol[type=decimal] { list-style-type: decimal; }
ol[type=lower-roman] { list-style-type: lower-roman; }
ol[type=upper-roman] { list-style-type: upper-roman; }
ol[type=lower-alpha] { list-style-type: lower-alpha; }
ol[type=upper-alpha] { list-style-type: upper-alpha; }

/* ==== 表格（15.3.8；边框绘制与列宽属 P3-17～P3-21）==== */
table { display: table; border-spacing: 2px; border-collapse: separate; }
tr { display: table-row; }
/* 单元格竖直居中（Chrome UA：td/th 为 `vertical-align: middle`，
   经 tr/tbody 的 inherit 得到；这里直接写在单元格上，效果一致，
   由表格排版层按单元格样式消费）。 */
td, th { display: table-cell; padding: 1px; vertical-align: middle; }
thead, tbody, tfoot { display: table-row-group; }
colgroup, col { display: table-column; }
caption { display: table-caption; text-align: center; }
th { font-weight: bold; text-align: center; }
table, td, th { border-color: gray; }
td[nowrap], th[nowrap] { white-space: nowrap; }

/* ==== 表单（15.3.10；真实书极少，最小集）==== */
fieldset { margin: 0 2px; padding: 0.35em 0.75em 0.625em; }
legend { padding: 0 2px; }
input, select, button, textarea { font-size: 0.83em; }

/* ==== 短语内容（15.3.4）==== */
b, strong { font-weight: bolder; }
i, em, cite, dfn, var { font-style: italic; }
code, kbd, samp, tt { font-family: monospace; }
pre { font-family: monospace; }
small { font-size: 0.83em; }
big { font-size: 1.17em; }
sub { font-size: 0.83em; vertical-align: sub; }
sup { font-size: 0.83em; vertical-align: super; }
u, ins { text-decoration: underline; }
del, s, strike { text-decoration: line-through; }
mark { background-color: yellow; color: black; }
abbr[title] { text-decoration: dotted underline; }
nobr { white-space: nowrap; }
br[clear=all], br[clear=both] { clear: both; }
br[clear=left] { clear: left; }
br[clear=right] { clear: right; }

/* ==== 双向文字（15.3.5）==== */
bdi, output { unicode-bidi: isolate; }
bdo { unicode-bidi: isolate-override; }

/* ==== hr（15.3.11）==== */
/* 保留阅读器既有默认灰线，作为 UA 声明允许作者正常覆盖。 */
hr { color: gray; margin-top: 0.5em; margin-bottom: 0.5em; height: 1px; border-bottom: 1px solid #B0B0B0; }

/* ==== 嵌入内容（15.4）==== */
img, video { display: inline; }
audio, canvas, embed, iframe, object { display: none; }

/* ==== ruby（CSS Ruby 1；注音排版属 P8-08）==== */
rt { font-size: 50%; text-indent: 0; }
''';

List<CascadeRule>? _uaRulesCache;

/// 解析 UA 样式表为层叠规则（UA origin）；结果缓存复用。
List<CascadeRule> uaRules() => _uaRulesCache ??= CascadeRule.fromStylesheet(
  CssParser.parse(uaStylesheetCss),
  origin: CascadeOrigin.userAgent,
);

/// 当前管线可直接消费的块级 UA 覆盖层（P7-03）。
///
/// 只含「单一基准样式 + 块级 PageBlock」路径已消费的物理属性；
/// 行内 run 样式（b/code/em…）、列表标记、表格边框、ruby 等留在
/// [uaStylesheetCss] 里等对应接线任务启用（见 P7-UA表对照.md）。
abstract final class UaBlockDefaults {
  /// 块级标签 → 声明集；不在表内的标签返回空 Map。
  static Map<String, String> declarationsFor(String tag) =>
      _blockDeclarations[tag] ?? const <String, String>{};

  /// 在基准样式之上应用块级 UA 覆盖；无覆盖声明时返回 null。
  ///
  /// 构造方式与 [ReaderOverrides.apply] 一致：覆盖声明作为子样式的
  /// 显式属性，em 单位相对父级字号解算（阅读器字号设置仍是基准）。
  static ComputedStyle? apply(
    ComputedStyle base,
    String tag, {
    double? containingWidth,
  }) {
    final declarations = declarationsFor(tag);
    if (declarations.isEmpty) {
      return null;
    }
    return ComputedStyle(
      declarations,
      parent: base,
      explicitProperties: declarations.keys.toSet(),
      containingWidth: containingWidth ?? 0,
      rootFontSize: base.fontSize,
    );
  }

  static const Map<String, Map<String, String>> _blockDeclarations =
      <String, Map<String, String>>{
        // 标题：字号/加粗/上下边距/避页底（WHATWG 15.3.6 + Reeden 630 §2-5）。
        'h1': <String, String>{
          'font-size': '2em',
          'font-weight': 'bold',
          'margin-top': '0.67em',
          'margin-bottom': '0.67em',
          'page-break-after': 'avoid',
        },
        'h2': <String, String>{
          'font-size': '1.5em',
          'font-weight': 'bold',
          'margin-top': '0.83em',
          'margin-bottom': '0.83em',
          'page-break-after': 'avoid',
        },
        'h3': <String, String>{
          'font-size': '1.17em',
          'font-weight': 'bold',
          'margin-top': '1em',
          'margin-bottom': '1em',
          'page-break-after': 'avoid',
        },
        'h4': <String, String>{
          'font-size': '1em',
          'font-weight': 'bold',
          'margin-top': '1.33em',
          'margin-bottom': '1.33em',
          'page-break-after': 'avoid',
        },
        'h5': <String, String>{
          'font-size': '0.83em',
          'font-weight': 'bold',
          'margin-top': '1.67em',
          'margin-bottom': '1.67em',
          'page-break-after': 'avoid',
        },
        'h6': <String, String>{
          'font-size': '0.67em',
          'font-weight': 'bold',
          'margin-top': '2.33em',
          'margin-bottom': '2.33em',
          'page-break-after': 'avoid',
        },
        // 引用与图注容器：上下 1em、左右 40px（WHATWG 15.3.3）。
        'blockquote': <String, String>{
          'margin-top': '1em',
          'margin-bottom': '1em',
          'margin-left': '40px',
          'margin-right': '40px',
        },
        'figure': <String, String>{
          'margin-top': '1em',
          'margin-bottom': '1em',
          'margin-left': '40px',
          'margin-right': '40px',
        },
        'figcaption': <String, String>{
          'margin-top': '1em',
          'margin-bottom': '1em',
        },
        // 预格式化：等宽字体（white-space 已由聚合器按 pre 语义处理）。
        'pre': <String, String>{
          'font-family': 'monospace',
          'margin-top': '1em',
          'margin-bottom': '1em',
        },
        // 列表容器与定义列表（标记绘制属 P3-23，先落缩进/边距/加粗）。
        'ul': <String, String>{
          'margin-top': '1em',
          'margin-bottom': '1em',
          'padding-left': '40px',
        },
        // 列表项（P3-23）：flat 管线无 ul 盒子，margin-left 40px 近似
        // ul padding-left 缩进；标记由章节源按列表类型赋值绘制。
        'li': <String, String>{
          'margin-left': '40px',
          'list-style-type': 'disc',
        },
        'ol': <String, String>{
          'margin-top': '1em',
          'margin-bottom': '1em',
          'padding-left': '40px',
        },
        'dl': <String, String>{
          'margin-top': '1em',
          'margin-bottom': '1em',
        },
        'dd': <String, String>{'margin-left': '40px'},
        'dt': <String, String>{'font-weight': 'bold'},
        // 表头单元格（表格排版属 P3-17～21，先落字体语义）。
        'th': <String, String>{'font-weight': 'bold', 'text-align': 'center'},
        // 分隔线：与 UA 层叠路径共用既有默认灰线（绘制属 P3-24）。
        'hr': <String, String>{
          'margin-top': '0.5em',
          'margin-bottom': '0.5em',
          'height': '1px',
          'border-bottom': '1px solid #B0B0B0',
        },
        // 居中表现属性（WHATWG 15.3.3）。
        'center': <String, String>{'text-align': 'center'},
        // 水平分割线外的水平线语义由 hr 承担；p 的默认段距待 P4-21
        // 阅读器段距设置接入后再启用（§7.5 第 3 条），不在覆盖层。
      };
}
