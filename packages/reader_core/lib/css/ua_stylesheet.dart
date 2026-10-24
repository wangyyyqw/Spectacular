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
/* ==== 隐藏元素（WHATWG HTML 15.3.1）==== */
/* 解析器按脚本可用把 noscript 解析成原始文本，样式须与 DOM 层一致；
   与 Chrome 行为一致（Reeden 630 号 §2 差异 1）。 */
noscript { display: none; }
area, basefont, datalist, noframes, param { display: none; }

/* ==== 页面（15.3.2；边距由阅读器设置接管，Reeden 630 号 §4-3）==== */
body { margin: 0; }

/* ==== 排版前注入（P7-25；对照 Reeden 必配注入样式，630 号 §4-3）====
   html/body 基础约束 + body 建立 BFC（flow-root）：阻断作者页面的
   裸 float/负 margin 污染整章——块流引擎中由「页根容器钳制首元素负
   margin（§60.7）+ UA origin 优先级」承担同一语义。 */
html, body { overflow: hidden; min-height: 0; height: auto; }
body { display: flow-root; }

/* ==== 流内容（15.3.3）==== */
/* 段落上下边距：段距按阅读器设置归一（技术方案 §7.5 第 3 条），
   覆盖层暂不启用 p 的默认段距，登记待 P4-21 设置项接入。 */
p { margin-top: 1em; margin-bottom: 1em; }
blockquote, figure { margin-top: 1em; margin-bottom: 1em; margin-left: 40px; margin-right: 40px; }
pre { margin-top: 1em; margin-bottom: 1em; }

/* ==== 分节与标题（15.3.6）==== */
/* 字号 2.00/1.50/1.17/1.00/0.83/0.67em、上下边距 0.67/0.83/1.00/
   1.33/1.67/2.33em 取自 WHATWG 渲染建议；
   标题避开页底（break-after: avoid）采纳自 Reeden（architecture 6.3，
   630 号 §2 差异 5），一期用 P0 属性 page-break-after 表达。 */
h1 { font-size: 2em; font-weight: bold; margin-top: 0.67em; margin-bottom: 0.67em; page-break-after: avoid; }
h2 { font-size: 1.5em; font-weight: bold; margin-top: 0.83em; margin-bottom: 0.83em; page-break-after: avoid; }
h3 { font-size: 1.17em; font-weight: bold; margin-top: 1em; margin-bottom: 1em; page-break-after: avoid; }
h4 { font-size: 1em; font-weight: bold; margin-top: 1.33em; margin-bottom: 1.33em; page-break-after: avoid; }
h5 { font-size: 0.83em; font-weight: bold; margin-top: 1.67em; margin-bottom: 1.67em; page-break-after: avoid; }
h6 { font-size: 0.67em; font-weight: bold; margin-top: 2.33em; margin-bottom: 2.33em; page-break-after: avoid; }

/* ==== 列表（15.3.7）==== */
/* 嵌套类型 disc→circle→square（CSS Lists 3 §4.3；标记绘制属 P3-23），
   嵌套选择器为样式表路径预留；覆盖层只取缩进与边距。 */
ul, ol { margin-top: 1em; margin-bottom: 1em; padding-left: 40px; }
dl { margin-top: 1em; margin-bottom: 1em; }
dd { margin-left: 40px; }
dt { font-weight: bold; }

/* ==== 表格（15.3.8；边框绘制与列宽属 P3-17～P3-21）==== */
/* th 加粗居中与 td/th 的 1px 内边距、2px 边距取自 WHATWG；
   裸表格网格线（无作者样式时补默认边框）随 P3 表格任务落地。 */
th { font-weight: bold; text-align: center; }

/* ==== 短语内容（15.3.4；行内 run 样式随逐 run 层接线启用）==== */
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

/* ==== hr（15.3.11；边框绘制属 P3-24）==== */
hr { margin-top: 0.5em; margin-bottom: 0.5em; }

/* ==== 居中（15.3.3 表现属性；div[align] 需属性选择器，随 P7-04 评估）==== */
center { text-align: center; }

/* ==== ruby（CSS Ruby 1；注音排版属 P5-01～P5-04）==== */
/* Reeden 的注音盒是独立块容器，故把继承来的段首缩进归零并限 50% 字号
   （630 号 §2 差异 4）；本项目是行内覆盖模型，先登记规则待 P5 接线。 */
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
        // 分隔线：上下 0.5em（绘制属 P3-24）。
        'hr': <String, String>{
          'margin-top': '0.5em',
          'margin-bottom': '0.5em',
        },
        // 居中表现属性（WHATWG 15.3.3）。
        'center': <String, String>{'text-align': 'center'},
        // 水平分割线外的水平线语义由 hr 承担；p 的默认段距待 P4-21
        // 阅读器段距设置接入后再启用（§7.5 第 3 条），不在覆盖层。
      };
}
