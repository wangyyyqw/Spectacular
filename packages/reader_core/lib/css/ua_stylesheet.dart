import 'cascade.dart';
import 'computed_style.dart';
import 'parser.dart';

/// UA 默认样式表（P7-03）。
///
/// 规则文本按 WHATWG HTML 15.3（渲染建议）分节，UA-001～UA-078 为稳定规则 ID。
/// 来源、支持状态及回归映射见 docs/UA规则台账-2026-11-07.md；
/// 本轮只补审计元数据，不改变声明顺序或作者覆盖行为。
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
/* UA-001；HTML 15.3.1；支持隐藏。 */
noscript { display: none !important; }
/* UA-002；HTML 15.3.1；支持隐藏。 */
area, base, basefont, datalist, head, link, meta, noembed, noframes,
param, rp, script, style, template, title { display: none; }
/* UA-003；HTML 15.3.1；支持隐藏。 */
[hidden] { display: none; }
/* UA-004；HTML 15.3.1；支持隐藏。 */
input[type=hidden] { display: none; }
/* UA-005；HTML 15.3.1；支持隐藏。 */
dialog:not([open]) { display: none; }

/* ==== 页面（15.3.2；边距由阅读器设置接管，Reeden 630 号 §4-3）==== */
/* UA-006；HTML 15.3.2；支持块与边距。 */
html, body { display: block; }
/* UA-007；HTML 15.3.2；支持块与边距。 */
body { margin: 0; }

/* ==== 排版前注入（P7-25；对照 Reeden 必配注入样式，630 号 §4-3）====
   html/body 基础约束 + body 建立 BFC（flow-root）：阻断作者页面的
   裸 float/负 margin 污染整章。 */
/* UA-008；阅读器策略；支持页根约束。 */
html, body { overflow: hidden; min-height: 0; height: auto; }
/* UA-009；阅读器策略；支持页根约束。 */
body { display: flow-root; }

/* ==== 流内容（15.3.3）==== */
/* UA-010；HTML 15.3.3；支持盒与文字样式。 */
p { margin-top: 1em; margin-bottom: 1em; }
/* UA-011；HTML 15.3.3；支持盒与文字样式。 */
blockquote, figure, listing, plaintext, pre, xmp {
  margin-top: 1em; margin-bottom: 1em;
}
/* UA-012；HTML 15.3.3；支持盒与文字样式。 */
blockquote, figure { margin-left: 40px; margin-right: 40px; }
/* UA-013；HTML 15.3.3；支持盒与文字样式。 */
address { font-style: italic; }
/* UA-014；HTML 15.3.3；支持盒与文字样式。 */
pre { white-space: pre; }

/* ==== 表现属性（15.3.3 表；P8-03 属性选择器落地）==== */
/* UA-015；HTML 15.3.3；支持对齐。 */
p[align=left], div[align=left], h1[align=left], h2[align=left],
h3[align=left], h4[align=left], h5[align=left], h6[align=left],
table[align=left] { text-align: left; }
/* UA-016；HTML 15.3.3；支持对齐。 */
p[align=center], div[align=center], h1[align=center], h2[align=center],
h3[align=center], h4[align=center], h5[align=center], h6[align=center],
table[align=center] { text-align: center; }
/* UA-017；HTML 15.3.3；支持对齐。 */
p[align=right], div[align=right], h1[align=right], h2[align=right],
h3[align=right], h4[align=right], h5[align=right], h6[align=right],
table[align=right] { text-align: right; }
/* UA-018；HTML 15.3.3；支持对齐。 */
center { text-align: center; }

/* ==== 分节与标题（15.3.6）==== */
/* 字号 2.00/1.50/1.17/1.00/0.83/0.67em、上下边距 0.67/0.83/1.00/
   1.33/1.67/2.33em 取自 WHATWG 渲染建议；
   标题避开页底（break-after: avoid）采纳自 Reeden（architecture 6.3，
   630 号 §2 差异 5）。 */
/* UA-019；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
h1 { font-size: 2em; font-weight: bold; margin-top: 0.67em; margin-bottom: 0.67em; page-break-after: avoid; }
/* UA-020；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
h2 { font-size: 1.5em; font-weight: bold; margin-top: 0.83em; margin-bottom: 0.83em; page-break-after: avoid; }
/* UA-021；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
h3 { font-size: 1.17em; font-weight: bold; margin-top: 1em; margin-bottom: 1em; page-break-after: avoid; }
/* UA-022；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
h4 { font-size: 1em; font-weight: bold; margin-top: 1.33em; margin-bottom: 1.33em; page-break-after: avoid; }
/* UA-023；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
h5 { font-size: 0.83em; font-weight: bold; margin-top: 1.67em; margin-bottom: 1.67em; page-break-after: avoid; }
/* UA-024；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
h6 { font-size: 0.67em; font-weight: bold; margin-top: 2.33em; margin-bottom: 2.33em; page-break-after: avoid; }
/* UA-025；HTML 15.3.6 / 阅读器策略；支持标题与避页底。 */
hgroup > p { margin-top: 1em; margin-bottom: 1em; }

/* ==== 列表（15.3.7；嵌套类型 disc→circle→square，CSS Lists 3 §4.3）==== */
/* UA-026；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
li { display: list-item; }
/* 刻意差异（flat 管线近似）：WHATWG li 默认 margin 0、缩进来自
   ul 的 padding；flat 无嵌套盒子，li 自带 40px 左边距承担缩进
   （P3-23 标记 gutter 语义），与旧 UaBlockDefaults 一致。 */
/* UA-027；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
li { margin-left: 40px; }
/* UA-028；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul ul, ul ol, ol ul, ol ol { margin-top: 0; margin-bottom: 0; }
/* UA-029；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul, ol { margin-top: 1em; margin-bottom: 1em; padding-left: 40px; }
/* UA-030；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
dl { margin-top: 1em; margin-bottom: 1em; }
/* UA-031；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
dd { margin-left: 40px; }
/* UA-032；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
dd + dt, dt + dt { margin-top: 0.5em; }
/* UA-033；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
dt { font-weight: bold; }
/* UA-034；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul { list-style-type: disc; }
/* UA-035；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ol { list-style-type: decimal; }
/* UA-036；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul[type=none], ol[type=none] { list-style-type: none; }
/* UA-037；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul[type=disc] { list-style-type: disc; }
/* UA-038；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul[type=circle] { list-style-type: circle; }
/* UA-039；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ul[type=square] { list-style-type: square; }
/* UA-040；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ol[type=decimal] { list-style-type: decimal; }
/* UA-041；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ol[type=lower-roman] { list-style-type: lower-roman; }
/* UA-042；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ol[type=upper-roman] { list-style-type: upper-roman; }
/* UA-043；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ol[type=lower-alpha] { list-style-type: lower-alpha; }
/* UA-044；HTML 15.3.7；支持；li 缩进为旧路径近似。 */
ol[type=upper-alpha] { list-style-type: upper-alpha; }

/* ==== 表格（15.3.8；边框绘制与列宽属 P3-17～P3-21）==== */
/* UA-045；HTML 15.3.8；支持表格样式。 */
table { display: table; border-spacing: 2px; border-collapse: separate; }
/* UA-046；HTML 15.3.8；支持表格样式。 */
tr { display: table-row; }
/* 单元格竖直居中（Chrome UA：td/th 为 `vertical-align: middle`，
   经 tr/tbody 的 inherit 得到；这里直接写在单元格上，效果一致，
   由表格排版层按单元格样式消费）。 */
/* UA-047；HTML 15.3.8；支持表格样式。 */
td, th { display: table-cell; padding: 1px; vertical-align: middle; }
/* UA-048；HTML 15.3.8；部分：角色由表格构块按标签消费，display 枚举不单独建盒。 */
thead, tbody, tfoot { display: table-row-group; }
/* UA-049；HTML 15.3.8；部分：角色由表格构块按标签消费，display 枚举不单独建盒。 */
colgroup, col { display: table-column; }
/* UA-050；HTML 15.3.8；支持表格样式。 */
caption { display: table-caption; text-align: center; }
/* UA-051；HTML 15.3.8；支持表格样式。 */
th { font-weight: bold; text-align: center; }
/* UA-052；HTML 15.3.8；支持表格样式。 */
table, td, th { border-color: gray; }
/* UA-053；HTML 15.3.8；支持表格样式。 */
td[nowrap], th[nowrap] { white-space: nowrap; }

/* ==== 表单（15.3.10；真实书极少，最小集）==== */
/* UA-054；HTML 15.3.10；部分：样式可用，无交互控件。 */
fieldset { margin: 0 2px; padding: 0.35em 0.75em 0.625em; }
/* UA-055；HTML 15.3.10；部分：样式可用，无交互控件。 */
legend { padding: 0 2px; }
/* UA-056；HTML 15.3.10；部分：样式可用，无交互控件。 */
input, select, button, textarea { font-size: 0.83em; }

/* ==== 短语内容（15.3.4）==== */
/* UA-057；HTML 15.3.4；支持文字样式。 */
b, strong { font-weight: bolder; }
/* UA-058；HTML 15.3.4；支持文字样式。 */
i, em, cite, dfn, var { font-style: italic; }
/* UA-059；HTML 15.3.4；支持文字样式。 */
code, kbd, samp, tt { font-family: monospace; }
/* UA-060；HTML 15.3.4；支持文字样式。 */
pre { font-family: monospace; }
/* UA-061；HTML 15.3.4；支持文字样式。 */
small { font-size: 0.83em; }
/* UA-062；HTML 15.3.4；支持文字样式。 */
big { font-size: 1.17em; }
/* UA-063；HTML 15.3.4；支持文字样式。 */
sub { font-size: 0.83em; vertical-align: sub; }
/* UA-064；HTML 15.3.4；支持文字样式。 */
sup { font-size: 0.83em; vertical-align: super; }
/* UA-065；HTML 15.3.4；支持文字样式。 */
u, ins { text-decoration: underline; }
/* UA-066；HTML 15.3.4；支持文字样式。 */
del, s, strike { text-decoration: line-through; }
/* UA-067；HTML 15.3.4；支持文字样式。 */
mark { background-color: yellow; color: black; }
/* UA-068；HTML 15.3.4；支持文字样式。 */
abbr[title] { text-decoration: dotted underline; }
/* UA-069；HTML 15.3.4；支持文字样式。 */
nobr { white-space: nowrap; }
/* UA-070；HTML 15.3.4；支持文字样式。 */
br[clear=all], br[clear=both] { clear: both; }
/* UA-071；HTML 15.3.4；支持文字样式。 */
br[clear=left] { clear: left; }
/* UA-072；HTML 15.3.4；支持文字样式。 */
br[clear=right] { clear: right; }

/* ==== 双向文字（15.3.5）==== */
/* UA-073；HTML 15.3.5；仅保存 unicode-bidi，未消费。 */
bdi, output { unicode-bidi: isolate; }
/* UA-074；HTML 15.3.5；仅保存 unicode-bidi，未消费。 */
bdo { unicode-bidi: isolate-override; }

/* ==== hr（15.3.11）==== */
/* 保留阅读器既有默认灰线，作为 UA 声明允许作者正常覆盖。 */
/* UA-075；HTML 15.3.11 / 阅读器策略；支持默认线与作者覆盖。 */
hr { color: gray; margin-top: 0.5em; margin-bottom: 0.5em; height: 1px; border-bottom: 1px solid #B0B0B0; }

/* ==== 嵌入内容（15.4）==== */
/* UA-076；HTML 15.4 / 阅读器策略；支持图片；视频无播放控件。 */
img, video { display: inline; }
/* UA-077；HTML 15.4 / 阅读器策略；按阅读器策略隐藏。 */
audio, canvas, embed, iframe, object { display: none; }

/* ==== ruby（CSS Ruby 1；注音排版属 P8-08）==== */
/* UA-078；CSS Ruby 1；支持注音文字。 */
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
/// 行内 run、完整列表、表格与 ruby 由 [uaStylesheetCss] 的层叠路径消费；
/// 此兼容入口仅用于块级基准样式，既有差异在 UA 台账中逐项记录。
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
