# EPUB CSS USB 真机验收

日期：2026-10-29。引擎基线：`eaa2ff06005cd77d75de46a2ac951e040b088a94`。

## 环境与范围

- 魅族 20，Android 16 / API 36，USB，1080×2400，DPR 2.8125。
- 《诸神愚戏》原书 155,677,829 字节，第 6 章“道具”，spineIndex 32。
- 使用真实 `EpubReaderPage`，内存阅读进度；正文宽度 344dp。
- 自动操作在 debug 构建运行，另以 `adb screencap` 复核正常渲染表面。

## 结果

| 场景 | 证据 | 结果 |
|---|---|---|
| 评级表 | 全章 76 张表的宽度加水平边距均不超过正文宽度 | 通过 |
| 嵌套卡片 | 三层容器背景保留，正文不重复承担容器边框 | 通过 |
| 效果框 | “恐惧养料”名称与说明共享容器，容器各有唯一首末片段 | 通过 |
| 连续翻页 | 逐页点击遍历 29 页，页序递增、内容非空，再反向翻页 | 通过 |
| 字号重排 | 实际拖动滑块，17→22，29→40 页；仍在目标章节，76 张表未越界 | 通过 |
| 图像复核 | 首三页及放大字号截图；第二轮系统直接截图排除测试表面转换的叠影 | 通过 |

首轮自动流程耗时约 54 秒，系统截图复测约 58 秒，不含构建安装。
修正后的隔离入口再次运行通过（约 55 秒），正式应用安装路径前后一致。
这是功能验证，不作为 release 性能数据。未覆盖横屏、其他设备和全书所有样式。

本地证据不入库：

- `/tmp/spectacular-usb-css/results/report.json`：首轮结构化结果。
- `/tmp/spectacular-usb-css/native/report.json`：系统截图复测结果。
- `/tmp/spectacular-usb-css/native/chapter6-page-2.png`：效果框正文系统截图。
- `/tmp/spectacular-usb-css/guarded-drive.log`：隔离入口复测日志。
- `/tmp/spectacular-usb-css/guarded/report.json`：隔离入口复测结果。

## 测试流程事故及恢复

首轮仅修改 `applicationId`，没有修改 `namespace`。当前 Flutter SDK 在首次构建前
从 namespace 取得清理目标，构建后却安装实际 APK 包名；`flutter drive` 结束时默认
执行卸载，导致原应用被误卸载。此事故属于测试执行失误，不是 EPUB 引擎缺陷。

用户选择恢复 10 月 26 日旧备份。已恢复三本原书与封面、3 条阅读进度、5 条标注记录
（其中包含书签）、8 项设置。恢复后的这些表逐行与备份一致，三本 EPUB 的 SHA-256
与恢复源一致；数据库完整性、外键检查通过，并成功迁移到 schema 5。
旧备份中损坏的废弃搜索缓存没有恢复，该缓存本就由 schema 5 删除。

已重建并安装当前修复版 release APK，确认书架显示三本书。**本次测试前的最新数据
没有备份，无法恢复 10 月 26 日之后的变动。**恢复材料保存在
`apps/reader_mobile/dist/recovery-20261029/recovery.tar`，不提交书籍或用户数据。

## 后续执行入口

使用仓库根目录的隔离入口，不直接在日常使用的应用包上运行集成测试：

```sh
python3 tool/device_css_test.py --device 381QYGE4224AA
```

需要 PATH 中有 `flutter`、`adb`、`apkanalyzer`，本地已缓存项目依赖和原书。
可通过 `--book`、`--output` 指定 EPUB 和输出目录。

入口复制当前代码到临时目录，同步修改测试包 namespace、applicationId、Activity，
构建后用 `apkanalyzer` 校验实际包名。驱动使用已校验 APK 和 `--keep-app-running`，
结束仅停止测试包，**不卸载任何应用**；同时校验正式应用安装路径保持不变。
测试图片与 JSON 默认写入已忽略的 `apps/reader_mobile/dist/css-device-results`。

## 阅微截图对照：跨页卡片续框

同日追加，代码基线 `0db0fb9`。截图中的大框是嵌套容器，道具名称与评级是单行表格。
普通横排的带框容器现在每页补齐上下边框与内边距，末片按实际内容收口；卡片首个
短标题与至少一行正文同页。表格预切也预留祖先装饰和自身盒模型占高。段距只在
真实首尾出现，续页不重复外边距。分页索引升级到 schema 2，旧边界自动重建。

本实现采用阅读器兼容策略：带框容器默认续框，尊重作者显式 `box-decoration-break:
slice`；显式 `clone` 可用于无框容器。分页预留边框和内边距的处理依据
[CSS Fragmentation 装饰分片规则](https://www.w3.org/TR/css-break-3/#break-decoration)。
存在浮动、竖排、分栏、绝对或固定定位的章节沿用原切片方式，尚未扩展该策略。

| 验证 | 结果 |
|---|---|
| 核心布局、绘制回归 | 673 项通过，1 项已有 Flutter 行高能力用例跳过 |
| 阅读管线回归 | 245 项通过，1 项未启用的全语料测试跳过；本书专项实际运行 |
| 改动文件静态检查、Python 语法 | 通过 |
| 默认字号 17 | 31 页，76 张表，30 个续页页尾完整预留装饰 |
| 字号 22 | 45 页，76 张表，44 个续页页尾完整预留装饰 |
| 翻页、反向翻页、章节位置、标题避断 | 全部通过；每页高度不超过正文区 |
| 缓存重放 | 嵌套框行边界、上下占位和页高一致，旧版索引被拒绝 |
| 正常 Android 表面截图 | 首三页及放大字号复核，续框留白和自然收口正常 |

本轮自动流程约 58 秒，不含构建安装。隔离入口前后正式应用安装路径一致。
Flutter 表面转图片的截图接口在该设备会产生旧帧叠影；入口已改为检查点同步请求
宿主 `adb exec-out screencap -p`，直接捕获正常表面。新流程不进行表面转换。

本地证据不入库：`/tmp/spectacular-usb-css/fragment-native/` 内有首三页、放大字号
PNG 和 `report.json`；日志分别为 `/tmp/spectacular-usb-css/fragment-native-drive.log`、
`/tmp/spectacular-fragment-core.log`、`/tmp/spectacular-fragment-app.log`。
Release APK 构建通过，手机正式版使用 `adb install -r` 覆盖更新，保留已有应用数据。


## 第三章“天赋”及全书 CSS 审计

范围：原书全部 8 个 CSS、3,283 条规则、17,556 条普通声明、86 种属性、111 个
`@font-face` 声明；并运行仓库现有 70 组 CSS 对照用例。第三章定位为 spine 29。
这不是逐页验证 1,541 章，也不是完整 CSS 标准兼容认证。

全量解析清点没有发现天赋规则丢失。20 条拒绝声明来自 8 类书源非法值，例如
`padding:auto`、`float:center`、错误颜色；两个样式表有多余右括号，解析器恢复后
仍完整保留后续天赋规则。属性被解析接受不代表布局或绘制已正确实现。

直接对原 DOM 级联的基准（16px 根字号）：正文 `.t-desc` 为 12.8px、20.48px 行高、
`#c5ccda`、两端对齐、零首行缩进；`.t-tag` 为 10.24px，上下 padding 1px、左右
4px、右 margin 5px、nowrap、inline-block。这些值用于检查扁平排版管线。

本轮修复：

- 无尺寸 inline-block 标签按内容收缩为独立盒，边框、内外边距参与断行；表格内等级标签走同一盒模型。
- 行内标记保留 id、style 和属性选择器数据；嵌套标记采用最深级联，不再被外层覆盖。
- 行内提取不重复拼接块祖先，避免 em 字号重复缩小；移除单段仅提取 8 个标签的限制。
- 两端对齐及基线偏移保留作者行内颜色；本书橙色 `.fmsA3` 出现 30,665 次、涉及 1,471 章。
- 行内标签补绘外阴影和内阴影；修复正文占位和表格纯标签绘制，避免盒内文字丢失或与后文重叠。
- 天赋顶边按不同宽度、颜色四边的斜接多边形绘制，恢复梯形角；分页索引升至 schema 3，使旧断行自动重建。
- 修复匹配器 nth-child 参数读取、first-of-type 和带 href 的 a:link，并补最小回归。

自动宽与水平外边距的实现依据：[CSS 2 inline-block 宽度](https://www.w3.org/TR/CSS2/visudet.html#inlineblock-width)、
[行内格式化上下文](https://www.w3.org/TR/CSS2/visuren.html#inline-formatting)。

全量浏览器对照的修前基线为 65 项几何/样式失配，涉及 10 组用例；29 组像素差异
超过 2%，3 个块未配对。像素差异受字体、抗锯齿、连续流与分页差异影响，不能直接
等同缺陷数量。逐用例证据位于 `/tmp/css-parity-audit-20261029/report.md`。

| 尚未解决或未完整实现的范围 | 审计结论 |
|---|---|
| 连字符、嵌套 quotes、word-wrap、text-overflow | 对照仍存在断行或尺寸差异，需各自最小复现继续处理 |
| small-caps/连字、tab-size、部分行高、着重号 | 仍有几何差异，不能宣称与浏览器一致 |
| display/position、表格、3D 边框 | 对照仍有残余失配，详见逐例报告 |
| backdrop-filter | 使用页背景近似，未实现真实背后内容过滤 |
| background-clip:text | 降级到 padding-box |
| 普通行内 run 的背景图/渐变、变换、百分比圆角 | 仍有近似处理，独立 inline-block 支持更完整 |
| z-index、多重阴影 | 非完整 stacking context；阴影仅保留首个 |

下一步以对照报告的残余失配分别建立最小复现，优先排查实际书籍命中的断行与表格问题。

补充边界：Flex 的 align-items/justify-content 尚无布局消费者；本书该规则仅为未使用的
占位图。静态分页未单独实现 background-attachment，私有字体平滑属性无消费者。
行内结构选择器缺少完整兄弟树，核心匹配器修复不能代表其端到端支持；display:block
的 span 尚未完整重建块级树。带行内盒的文字装饰线和命中坐标也需继续审计。

最终本地验证：CSS/解析/布局 678 项、绘制 241 项、阅读管线 252 项通过，共 1,171 项；
2 项既有条件用例跳过。改动源文件静态检查无问题，release APK 构建成功。
70 组对照复跑仍为 65 项几何/样式失配、29 组显著像素差异，**未清零**；本轮真实书
标签与角接缝缺陷由新增真实书和像素回归覆盖，不能用旧对照集的通过率代替验收。


最终 USB 验收（魅族20，约95秒，不含构建）：第三章19页逐页及反向翻页通过，正文17px、
标签13.6px、右外边距5px；首三页系统截图确认等级字样正常、标签不与后文重叠、橙金顶边
两端斜接为梯形。第六章32页、76张表；字号22时45页，整章占高与续框断言通过。
证据目录 `/tmp/spectacular-css-audit-device-final/`，含7张PNG和report.json；
日志 `/tmp/spectacular-css-audit-device-final.log`。测试包隔离，前后正式应用路径一致。
本轮先由真机发现字号覆盖后的相对继承错误，再补17/22字号回归修复，未放宽失败断言。
Release版本采用保留数据的覆盖安装。边框斜接参考
[W3C 边框颜色与样式过渡](https://www.w3.org/TR/css-backgrounds-3/#corner-transitions)。

## 用户截图定点复核：吊命与第二神

用户提供的20:27、20:28截图早于 `097c163` 修复版安装。本轮以相同原书复查具体位置，
新增专项回归，未再修改生产渲染代码。

- 第三章“吊命”（spine 29）：17/22px 设置下标签分别13.6/17.6px，颜色为
  `#9bb0d1`，右距5px，完整单盒占宽；手机原生截图确认标签与后文无重叠、无基线错位。
- 第四章“正神”的〖繁荣〗（spine 30）：`生命命途 · 第二神` 只有一个行内盒和一圈
  外框，原书未定义内部竖线。旧版按文字片段重复画边框，现独立盒路径已消除。
- 真机三项场景通过，约122秒；第四章10页，目标在第8页。正式 APK 的 SHA-256
  与已验证release一致，测试前后正式应用安装路径不变。

本地证据：`/tmp/spectacular-targeted-css/chapter3-diaoming.png`、
`/tmp/spectacular-targeted-css/chapter4-fanrong.png`、同目录 `report.json`；
日志 `/tmp/spectacular-targeted-css.log`。离屏复核亦确认标签金色长竖线仅存在于左右外边。
本轮仅验收这两个具体位置，之前全量CSS对照的残余差异仍按上节记录保留。
