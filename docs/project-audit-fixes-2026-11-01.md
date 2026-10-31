# 项目审计修复与性能验证（2026-11-01）

## 范围与结论

基线 `487d444`。本轮覆盖书库、归档与资源、字体、搜索与阅读交互，并测量真实
EPUB 的导入、打开、章节跳转及 CSS 背景定位。保留现有原生分页架构，未新增依赖，
未复制参考项目实现。十项审计问题均有修复和回归；不代表完整 CSS/CFI 兼容或
长书性能指标全部达成。

- 最终 `bash tool/run_all.sh`：三包分析无问题，core 1343、UI 178、app 470 项通过，
  合计 **1991 项通过、9 项条件跳过、0 失败**。
- MEIZU 20 / Android 16 正式 debug 覆盖安装成功，原有两本书保留；普通/表格
  搜索跳页、非首页选择、退出恢复、换书隔离及目录跳转已真机检查。
- 最终提交 `6ff1bb0` 同口径 release 三进程：九次打开正文/完全显示中位数
  **1465/1712 → 696/956ms**，正文约减少 52%；跳 30 正文 225 → 173ms，跳 32
  为 345 → 323ms。最新完整导入单次为 **1984 → 1291ms**，约减少 35%。
  阶段性数据另列，不混样本，不承诺其他设备或书籍的固定收益。
- 最后复测实际发现两次 debug 冷打开 ANR，未隐去失败：先消除缺失字体逐章重复
  解析，再把内容摘要改为分块让出。最终冷打开后立即触摸、加载中退出未新增 ANR；
  **debug 总计算时间仍较长**，不把响应恢复写成打开性能预算达标。

## 十项审计闭环

表中 app/core/UI 分别指 `apps/reader_mobile`、`packages/reader_core`、
`packages/reader_ui`，源码与测试路径相对对应包根。

| # | 原问题与影响 | 实现位置与处理 | 回归证据 |
|---|---|---|---|
| 1 | 标识为 `.`/`..` 时书目录落到父目录，递归删除范围扩大 | app `lib/library/library_store.dart`：点段稳定编码，创建/删除统一安全目录检查；异常旧记录只清库行 | `test/library/library_store_test.dart`：点段查重、删除后其他书/设置保留，旧库异常 ID 不越界删除 |
| 2 | 书架共用搜索服务导致换书串源，重复解包且无界保存全文 | app `lib/reader/epub_reader_page.dart` 持有服务并复用正文来源；`scan_search_service.dart` 代次取消；纯文本按 5 章 LRU | `test/home/bookshelf_search_lifecycle_test.dart`、`test/search/scan_search_service_test.dart`：换书、退出、在途取消、淘汰章回访 |
| 3 | 抽屉已关闭后再次 pop，点击搜索命中退出阅读路由 | UI `lib/reader_page.dart`：移除多余 pop，异步后检查 mounted | `test/reader_interaction_regression_test.dart`：命中后路由保留、临时高亮位置正确 |
| 4 | 选词/选句/全选/拖动默认记录第 0 页，非首页失效 | UI `lib/selection/selection.dart`、`selection_layer.dart`、`reader_page.dart` 完整传递真实页码 | 同一 UI 回归：第 2 页长按、选句、全选保留页码 |
| 5 | CFI 比较混入字符偏移，长段落跳错页 | UI `lib/reader_session.dart`：路径/偏移分离，扣除拆块基准；半开行范围兼容空行与文末 | 同一 UI 回归：零/非零基准的同段多页跳转，页首空行重排不退回首页 |
| 6 | 正文 padding 未同步到选区、手柄、菜单、标注 | UI `lib/reader_page.dart`、`selection_layer.dart` 统一坐标原点；边缘热区仍按整页 | 同一 UI 回归：绘制与拖拽命中、菜单、高亮、边缘跨页扩选 |
| 7 | 实际字体路径绕过解混淆；同标识不同书串族，增量注册/关闭有竞态 | app `epub_chapter_source.dart` 统一 `document.readFontBytes`；core `lib/css/book_font_loader.dart` 内容摘要隔离、串行合并、取消回填；新增 face 失效旧布局 | core `test/css/book_font_loader_test.dart`；app `test/reader/font_obfuscation_pipeline_test.dart`：IDPF/Adobe 像素等价、内容隔离、增量字重、并发与关闭 |
| 8 | 单条惰性 deflate 解压异常令未引用坏资源阻止整书打开 | core `lib/epub/archive_reader.dart` 按条目隔离解压/CRC 失败，全部坏仍拒绝 | `test/epub/archive_reader_test.dart`：注入真实坏 deflate 流，跳过坏资源、保留好章节，全部坏仍分级报错 |
| 9 | 嗅探修复仅写报告，后续资源读取仍失败 | core `lib/epub/resource_index.dart` 内存别名由 resolve/read 共用，同目录优先且必须唯一，不改写原书 | `test/epub/resource_repair_test.dart`：相对路径/片段读取、目录隔离、歧义拒绝、原书摘要不变 |
| 10 | encryption.xml 硬编码 `enc:`，合法前缀/默认命名空间失效 | core `lib/epub/font_obfuscation.dart` 按 namespace URI/local name 匹配 | `test/epub/font_obfuscation_test.dart`：任意/默认前缀等价，伪命名空间无效 |

导入 CRC 仍启用，没有通过取消校验换性能。当前 `archive 4.5.2` 内部 verify
路径没有实际执行 CRC 比较，项目自身校验不能删。

### 搜索定位补充

- 扫描原文与排版文字因隐藏/生成内容、换行、`text-transform` 可能不同。现在用
  真实变换后词生成候选，再按去空白上下文与全章命中序号消歧；UTF-16 偏移按实际
  变换后前缀长度计算，不套用扫描偏移。新增五组变换和一组混合重复词回归，旧实现失败。
- 真实天赋表的 RANK 位于单元格原子行内盒，外层 `layout.text` 为空。
  `apps/reader_mobile/lib/search/chapter_text.dart` 从实际表格/Flex 单元格递归还原
  可见文字，去重跨页复制载荷，不重复计算外层文本。
- `TableCellRender.startCfi` 保留真实元素来源，宿主预切表与 core 分页切片均透传；
  ReaderSession 按单元格路径精确定位页。九行分页表格逐项解析回 `rank0`～`rank8`
  元素并检查目标页，真实书 62 处 RANK 可搜索、可跳页。
- **表格只返回元素页锚点，不伪造格内字符 CFI 或高亮**；普通正文仍有字符级 CFI
  和临时高亮。跨页 rowspan、普通正文原子盒文字、复杂行内混合变换未全部覆盖，
  不把页级定位表述为任意 DOM 文本的字符级映射。

## 性能实现与口径

1. core `lib/position/text_length.dart`：逐字符字符串/正则改码元判定；全部 65536 个
   BMP 码元与 Dart `\s` 等价，代理对、实体/标签顺序、分帧让出及进度行为不变。
2. `EpubChapterSource.style` 在同尺寸/设置环境复用；尺寸、覆盖设置、关闭失效。
   app `test/cache_layer_test.dart` 验证复用、失效与颜色零重排。
3. core `lib/css/selector.dart` 按原始 class 字符串缓存分词，最多 128 条，长度大于
   1024 不入缓存，不持有树/元素；回归覆盖动态属性、空白/大小写、淘汰、超长值。
4. `tool/device_reader_perf.py` 显式 `--far-jump/--no-far-jump`，不按 revision 暗改
   测量条件；`--measure-import` 用隔离包临时真实书库，结束清临时 DB/目录。
5. `EpubChapterSource._readBookFont` 按首次出现顺序缓存独立章节目录，关闭时释放。
   真实书 1541 个 spine 只有一个 `Text` 目录，缺失字体每次兜底从 1541 次降至一次；
   仍保留直接路径/资源索引/章节目录顺序，成功后统一走解混淆入口。
6. `BookFontLoader` 复用 crypto 流式 SHA-256，以 64KiB 字节视图分块、块间让出事件
   循环并检查关闭代次；不新增 isolate/依赖，不改变内容摘要或引擎族名。新增摘要
   等价、事件抢占关闭两项测试；旧同步实现在关闭回归中失败。

未引入 ZIP 后端、新并发架构或跨节点布局缓存。EpubChapterSource 既有长编排函数
及字体 loader 原有注册循环暂不大拆：跨越样式/几何/异步状态，机械拆分扩大回归面。
已抽出小型读取/失效函数，但长函数仍是维护风险，不称其已通过本次审计消除。

### 阶段性 release 真机 A/B

MEIZU 20 / Android 16，Flutter 3.47.5 / Dart 3.13.4；同一真实书
`test_corpus/real/zhushen-yuxi.epub`，155677829 字节、1541 章。基线 `487d444`
与本轮工作树各三个独立进程，每进程打开三次，均显式 `--no-far-jump`，测试入口
一致。从书架动作计到正文帧及图片/淡入完成，不是应用冷启动或纯解析耗时。

以下六轮发生在最终表格来源元数据补充及字体热点修复之前，不能当作最终提交
逐字节对应的性能基准。单位 ms，格式「正文/完全显示」。

| 轮次 | 首次打开 | 再打开 1 | 再打开 2 | 跳 30 | 跳 47 | 回 29 | 跳 32 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 前 1 | 1600/1851 | 1464/1707 | 1463/1709 | 225/288 | 109/290 | 29/292 | 345/366 |
| 前 2 | 1496/1747 | 1450/1712 | 1480/1717 | 223/286 | 110/291 | 26/290 | 342/369 |
| 前 3 | 1581/1834 | 1465/1710 | 1422/1685 | 226/275 | 111/292 | 27/291 | 347/377 |
| 后 1 | 1550/1796 | 1515/1760 | 1463/1725 | 178/277 | 110/290 | 28/292 | 320/351 |
| 后 2 | 1570/1814 | 1431/1694 | 1433/1693 | 173/288 | 111/290 | 28/292 | 311/341 |
| 后 3 | 1552/1797 | 1457/1719 | 1466/1712 | 172/288 | 111/292 | 29/295 | 306/333 |
| 前中位数 | 1581/1834 | 1464/1710 | 1463/1709 | 225/286 | 110/291 | 27/291 | 345/369 |
| 后中位数 | 1552/1797 | 1457/1719 | 1463/1712 | 173/288 | 111/290 | 28/292 | 311/341 |

九次打开中位数 **1465/1712 → 1466/1725ms，无显著改善**。跳 30 正文约减少 23%，
但完全显示 286 → 288ms；跳 32 正文约减少 10%、完全显示 369 → 341ms，其他基本不变。
不以动画时延掩盖或夸大正文阶段收益。

六份原始报告在以下目录的 `report.json`，仅留本机，不提交日志/构建产物：

- `/tmp/spectacular-final-perf-before/`
- `/tmp/spectacular-final-perf-before-2/`
- `/tmp/spectacular-final-perf-import-before/`
- `/tmp/spectacular-final-perf-after/`
- `/tmp/spectacular-final-perf-import-after/`
- `/tmp/spectacular-final-perf-after-3/`

### 最终提交 release 三进程复测

字体目录去重与分块摘要提交后，使用源码 `6ff1bb0`、相同设备/真实书/测试入口、
显式 `--no-far-jump` 重跑三个独立进程，各打开三次。首轮含完整导入，后两轮不含，
与基线三轮同样覆盖一个导入样本；下载不计时，未改动画或采样条件。与基线比较
是同设备不同时段顺序实验，不是随机交错试验，不把收益全归分块调度。

| 轮次 | 首次打开 | 再打开 1 | 再打开 2 | 跳 30 | 跳 47 | 回 29 | 跳 32 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 最终 1 | 807/1066 | 695/772 | 662/742 | 173/288 | 110/290 | 28/292 | 325/359 |
| 最终 2 | 804/1064 | 696/956 | 675/756 | 184/447 | 112/291 | 27/290 | 323/352 |
| 最终 3 | 769/849 | 694/957 | 742/1004 | 172/287 | 111/290 | 27/291 | 311/335 |
| 最终中位数 | 804/1064 | 695/956 | 675/756 | 173/288 | 111/290 | 27/291 | 323/352 |
| 基线中位数 | 1581/1834 | 1464/1710 | 1463/1709 | 225/286 | 110/291 | 27/291 | 345/369 |

九次打开正文/完全显示中位数 **1465/1712 → 696/956ms**（约减少 52%/44%）。
跳 30 正文约减少 23%，完全显示未改善；跳 32 正文约减少 6%、完全显示约 5%。
最终 2 跳 30 完全显示有 447ms 波动，保留原样，不删慢样本。用中位数描述这本书，
不是任意 EPUB 打开预算或尾延迟保证；debug 冷打开仍需数秒，见 ANR 专节。

原始报告：`/tmp/spectacular-final-perf-committed/report.json`、
`/tmp/spectacular-final-perf-committed-2/report.json`、
`/tmp/spectacular-final-perf-committed-3/report.json`。

### 完整导入（阶段性与最终提交）

取前 3 / 后 2 各一次完整导入累计时间，含真实 LibraryStore 与导入后权重查询；
下载不计入导入，**不是三轮中位数**，存储与调度仍有波动。

| 阶段（累计 ms） | 前 | 后 |
|---|---:|---:|
| 读入字节 | 92 | 95 |
| 校验完成 | 677 | 677 |
| 落盘完成 | 967 | 845 |
| 字符统计完成 | 1943 | 1149 |
| 全流程完成 | 1984 | 1187 |
| 章节数 | 1541 | 1541 |
| 字符数（UTF-16） | 3707426 | 3707426 |

统计阶段 976 → 304ms；单次全流程约减少 40%。落盘缩短 122ms 不能全归扫描优化，
不承诺任意设备/EPUB 的固定提速比例。

最终提交再测累计读入 88、校验 672、落盘 953、统计 1254、全流程 **1291ms**，
章数/字符数仍为 1541/3707426；统计阶段为 301ms。对原基线 1984ms 约减少 35%，
与阶段样本 1187ms 不矛盾，属于不同时段单次波动，不取较快结果冒充最终值。

### CPU 与内存限制

macOS JIT 对真实 spine 29/30/47 各三轮清几何缓存：基础样式缓存后合计 2127ms，
class 分词缓存后 1962.6ms，页数仍 20/11/11；SelectorPart.matches inclusive 样本
289 → 29，ComplexSelector 323 → 60，总样本 1342 → 1230。证据为
`/tmp/spectacular-selector-profile-after.log`、`/tmp/spectacular-layout-profile.json`。
JIT 样本比例不是 Android AOT 提速比例。

阶段六轮常规检查点 RSS 约 466～519MiB；最终三轮为 **475～567MiB**（包括导入后
同进程打开），不是完整采样峰值；上一轮长书扫描峰值接近 600MiB。
**200MB 目标未达到**，本轮不宣称长书峰值下降。导入旧路径未统一 finally 关闭归档
也未处理，应与 ZIP/资源生命周期单独评估。

### 最终 debug ANR 发现与复测

- 源码 `6b44bf4` 覆盖安装后，2026-11-01 02:18:11 冷打开《诸神愚戏》并继续
  触摸时真实出现 `Input dispatching timed out`（MotionEvent 等待 5000ms）。
  这发生在打开阶段，尚未执行搜索，不误归因于搜索。ANR 栈的主线程在 Dart 代码，
  不是永久死锁；同一弹窗多次显示不重复计为多次事故。
- 首次 CPU 采样 5927 个、跨度 7.021s，`_readBookFont` inclusive 3144 个样本，
  `ResourceIndex.resolve` 2857 个。`d04b51f` 去重目录后对应为 25/88，热点已下降，
  但 02:35:12 **仍发生新的 ANR**；同期 SHA-256 `updateHash` 占 4403 个样本，
  仅去重目录不能判定修复成功。不同采样总数/JIT 状态不同，不将比例当作严格耗时。
- `6ff1bb0` 分块摘要后，同样冷进程打开、2 秒后送入一次中心触摸，CPU 采样中
  `updateHash` 仍有 4295 个样本（总 7309、跨度 8.578s），但工作跨事件循环执行。
  此后未新增 ANR，`lastanr` 仍停留在修复前 02:35:12；这说明恢复响应，不说明
  SHA 总成本消失或 debug 已达到 release 的打开耗时。
- 另一次不启用 profiler 的冷进程打开，2 秒后单次触摸，最终恢复第 3 章第 2/18 页；
  再次冷进程打开后 2 秒发送返回，正常回到两书书架，无新增 ANR。未卸载/清数据。
- 最终 APK 再查 RANK 得到 62 处，点击第二条“忆中故我”到第 3 章第 2/18 页，
  已人工查看截图：卡片文字/背景正常、阅读路由保留、无伪字符高亮。
- 原始证据：`/tmp/spectacular-committed-anr-dropbox.txt`（本轮在 2658 行起）、
  `/tmp/spectacular-anr-profile-open.json`、`/tmp/spectacular-font-directory-profile-open.json`、
  `/tmp/spectacular-font-hash-early-touch-profile-open.json`、
  `/tmp/spectacular-font-hash-lastanr-after1.txt`、
  `/tmp/spectacular-font-hash-lastanr-after2.txt`、
  `/tmp/spectacular-font-hash-lastanr-after-cancel.txt`。

这些是限定样本复测，不是长时稳定性或任意复杂书籍零 ANR 保证；同步 CSS 解析与
分页仍可能造成卡顿，继续列为性能风险，不用采样开关掩盖正式使用路径。

## CSS 与参考资料

ComputedStyle 背景位置现在按轴归一双关键字，top center/center top、bottom center/
center bottom、center left/left center 等价；长度/百分比仍先横后纵。复用原绘制，
未扩展三/四值边缘偏移语法。

- core `test/paint/background_position_keyword_test.dart` 五项回归：旧代码一过四败，
  新代码通过；覆盖解析、简写、多层、块级/整页绘制。
- 第 105 组浏览器对照墨迹形状差 **5.92% → 0.77%**，原始像素差
  **6.62% → 2.27%**，几何/样式失配 0。
- 最终 102 组完整重导：**0 几何/样式失配、0 未配对、墨迹 >2% 为 0**；原始像素
  >2% 仍 **29 组**，含字体栅格和连续流/分页范围差异。基线 101 组已经是 0 几何
  失配，不把之前成果算本轮清零；未改 compare、容差、skip。
- 属性矩阵 169 项中 153 项有用例引用（90.5%），不是渲染语义兼容率；生成幂等，
  Python 比较/矩阵工具七项通过。
- 真实 mj-003 制作说明 spine 1，`OEBPS/Styles/main.css:41` 的 bottom center + cover，
  图片 `OEBPS/Images/p0.jpg`（1080×2400）真机已解码，位置 x=50%、y=100%；
  背景与圆角卡片已人工查看。仅在隔离包运行，未导入正式库。

参考资料与证据级别：

- [Reeden 650](../参考/reeden/reports/650-rpi2-format.md) §0～2：区分〔明文〕schema、
  〔推导〕解释与〔建议〕，只参考分层/失效，不照搬协议或实现。
- [Reeden 130](../参考/reeden/reports/130-epub-css.md) §1～2：静态【观测】/【推断】
  不是动态性能或兼容证明，不复用代码。
- [阅微锚点分析](../方案/验收记录/阅微注释锚点分析.md)：维持项目 CFI 坐标约束，
  不另建并行坐标，实际结论以本项目 EPUB 与测试为准。
- [W3C Backgrounds 3 §2.6](https://www.w3.org/TR/css-backgrounds-3/#background-position)：
  双关键字轴序与长度/百分比顺序的规范依据。

## 复现与交付证据

仓库根执行，Flutter 测试/构建串行，避免共享原生产物竞争：

```sh
bash tool/run_all.sh
bash tool/check_core_boundary.sh
bash tests/analysis/verify_strict_flags.sh
bash tests/tool/verify_core_boundary.sh
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover \
  -s tests/tool -p 'css_parity_*_test.py'
CSS_PARITY_OUT=/tmp/spectacular-css-check node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/spectacular-css-check \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/spectacular-css-check /usr/bin/python3 tool/css_parity/compare.py
```

真机脚本必须指定连接设备，前后使用同一开关；不在仓库保存真实设备标识：

```sh
/usr/bin/python3 tool/device_reader_perf.py --device '<设备序列号>' \
  --revision 487d444 --no-far-jump --measure-import --output /tmp/reader-before
/usr/bin/python3 tool/device_reader_perf.py --device '<设备序列号>' \
  --no-far-jump --measure-import --output /tmp/reader-after
```

- 全量 `/tmp/spectacular-font-hash-run-all.log`；
  守卫 `/tmp/spectacular-font-hash-guards.log`；
  工具 `/tmp/spectacular-font-directory-python.log`；CSS `/tmp/spectacular-font-hash-css/report.md`。
  目录去重后浏览器/引擎 JSON/PNG 各 102 份与之前逐字节相同；分块摘要后引擎
  204 份重导仍相同，复用这一轮已实测的浏览器产物比较，未改容差。
- 九项条件跳过含显式开关的真实书/CSS/预算/采样及当前引擎行距能力限制；未改 skip。
  真实书/CSS 已另以真机和专用入口补测，不代表所有条件入口均运行。
- 从源码提交 `6ff1bb0` 重建的正式 debug 为 234847046 字节，SHA-256
  `ce395ee7b02053239403820ff63a694cc7e6cd21f1b7b0236ccb8e927dc8d3e6`；
  `install -r` 成功，lastUpdateTime 2026-11-01 02:42:30，firstInstallTime 保持
  2026-10-31 17:59:47，未卸载/清数据。
- 最新 RANK `/tmp/spectacular-device-font-hash-rank-hits-correct.xml/png`、
  `/tmp/spectacular-device-font-hash-rank-destination.xml/png`：第二条“忆中故我”落在
  第 3 章第 2/18 页，无伪字符高亮且路由保留。冷打开恢复见
  `/tmp/spectacular-device-font-hash-cold2-open.xml/png`；加载中退出见
  `/tmp/spectacular-device-font-hash-cancel-returned.xml/png`，两书仍保留。
  本轮两次 ANR 及修复后限定复测见前节，不用日志未见异常替代 ANR 核查。
  最后隔离 release 复测结束已停包，正式应用回书架；
  `/tmp/spectacular-device-audit-final-library.xml/png` 两书保留，
  `/tmp/spectacular-audit-final-lastanr.txt` 仍为修复前 02:35:12。
- 完整设备矩阵见[验收记录](../方案/验收记录/M2-审计修复与性能验证-2026-11-01.md)。

## 未处理风险与下一步

- 长书 RSS 未达标；debug 摘要虽已分块，CSS 解析/分页同步工作仍有卡顿风险。
  优先测清按需 ZIP/资源生命周期收益，再决定后端变更，不能移除 CRC。
- 表格只有页锚点，rowspan/复杂原子盒/混合变换未全验；CSS 三/四值背景定位、
  百分比高度等旧边界未扩展，不是完整浏览器兼容。
- flutter_tts 旧 KGP 有未来兼容警告，当前构建成功，未擅自升级依赖。
  用户既有 `方案/设计/阅读页与阅读菜单设计.md` 修改未动、未提交。
