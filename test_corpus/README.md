# 测试样本库

本目录是 P0-06 的产物：一组体积很小、可重复生成、可自动校验的 EPUB 样本，用于导入、解析、排版与容错测试。

**版权声明：所有样本的正文均为本项目自写原创文字，不含任何受版权保护的书籍段落，也不含从网络抓取的第三方内容。图片由生成脚本用标准库现场绘制。除 `broken-resource.epub` 标记为「自建测试样本」外，其余样本按 CC0-1.0 放弃著作权。**

## 1. 目录结构

```text
test_corpus/                 # 只放样本、清单与说明
├── README.md                # 本文件
├── manifest.json            # 样本清单（机器可读）
├── basic.epub
├── styles.epub
├── table.epub
├── toc-ncx.epub
├── broken-resource.epub
└── cjk-vertical.epub

tests/corpus/                # 生成与校验脚本
├── build_epubs.py           # 重新生成全部样本与 manifest
└── verify_epubs.sh          # 校验样本与 manifest
```

`test_corpus/` 中不放脚本、构建中间产物或临时文件；解包与打包过程都在系统临时目录完成。

## 2. 分类与样本清单

按「正常 / 复杂 / 破损」三类归档：

| 分类 | id | 文件 | 标题 | 覆盖点 |
|---|---|---|---|---|
| 正常 | `basic` | `basic.epub` | 山海小记 | EPUB3；OPF、spine、nav；三章纯文本；基础段落样式 |
| 正常 | `toc-ncx` | `toc-ncx.epub` | 旧式目录 | EPUB2；OPF 2.0；`toc.ncx` 与 NCX 指南；`guide`；无 nav |
| 复杂 | `styles` | `styles.epub` | 样式练习册 | 标题、粗体、斜体、颜色、行高、`text-indent`、`text-align`、`margin`、`blockquote` |
| 复杂 | `table` | `table.epub` | 表格与插图样例 | 带 `colspan` 的表头、`caption`、8×8 PNG 图片、图文混排 |
| 复杂 | `cjk-vertical` | `cjk-vertical.epub` | 竖排与注音 | `ruby` 注音、`writing-mode: vertical-rl` 竖排、中文标点 |
| 破损 | `broken-resource` | `broken-resource.epub` | 破损之书 | manifest 声明了不存在的图片；NCX 含指向不存在章节的坏链接 |

`broken-resource.epub` 是**故意**不合规的样本：ZIP 本身完整，但 manifest 中的 `images/missing.png` 没有写进压缩包，`toc.ncx` 的第二个 `navPoint` 指向不存在的 `text/chapter3.xhtml`。它只用于容错测试，不要拿它当正常渲染基线。

## 3. 来源与许可

| 项目 | 说明 |
|---|---|
| 正文 | 本项目自写原创短篇与说明性文字，无第三方来源 |
| 许可 | CC0-1.0（放弃著作权）；`broken-resource` 为「自建测试样本」 |
| 图片 | 生成脚本用 PNG 规范现场绘制 8×8 纯色图，无外部素材 |
| 字体 | 样本不内嵌字体，只引用通用 `serif` |
| 外部依赖 | 无。生成只用 Python 标准库与系统 `zip` 命令 |

选择自写文本而不是直接下载公版书，是为了让每个样本的篇幅、章节数和待测特性都可控，同时避免把整本公版书带进仓库。若后续需要真实公版书做长文与性能基线，应单独记录 Project Gutenberg 的来源 URL、下载日期与许可，并在 manifest 中逐条登记，不要覆盖本目录的现有样本。

## 4. OCF 打包约定

每个 EPUB 都按 OCF 要求生成：

1. `mimetype` 是 ZIP 的第一个条目，内容恰为 `application/epub+zip`（20 字节，无换行）；
2. 先执行 `zip -X0 <书名>.epub mimetype`，以 stored（不压缩）方式写入；
3. 再执行 `zip -Xr9 <书名>.epub META-INF OEBPS`，压缩其余资源；
4. 不使用 ZIP 注释、加密或额外字段。

`tests/corpus/verify_epubs.sh` 会检查第一条目、内容、压缩方式、本地头偏移与 extra field，并打印 `unzip -l` 与文件头 `od -c` 供人工复核。

## 5. 如何重新生成

在仓库根目录执行：

```bash
/usr/bin/python3 tests/corpus/build_epubs.py
```

- 要求 Python 3.9+，只用标准库；macOS 自带的 `/usr/bin/python3` 即可。
- 依赖系统 `zip` 命令（`/usr/bin/zip`）。
- 脚本会重建 6 个 `.epub` 并重写 `manifest.json`，其中 `sha256` 与 `size_bytes` 由实际文件计算，不需要手工维护。
- ZIP 会记录文件修改时间，因此每次重建后 `sha256` 都会变化，这是预期行为；提交时把 `.epub` 与 `manifest.json` 一起提交。
- 不要手工编辑 `.epub` 二进制，也不要手改 manifest 中的哈希；改内容请改 `build_epubs.py` 后重新生成。

## 6. 如何校验

在仓库根目录执行：

```bash
bash tests/corpus/verify_epubs.sh
```

依赖 `jq`、`unzip`、`zipinfo`、`shasum`（macOS 自带）。脚本逐项检查：

1. `manifest.json` 是合法 JSON，样本数不少于 6，9 个必需字段齐全且类型正确；
2. `broken-resource` 的 `license` 为「自建测试样本」；
3. 每个样本存在，`sha256` 与 `size_bytes` 和 manifest 完全一致，且小于 200KB；
4. `unzip -t` 通过，`unzip -l` 可正常列出内容；
5. `mimetype` 是第一个条目、内容正确、以 stored 保存、本地头偏移为 0、无 extra field；
6. 打印每个样本的 `unzip -l` 与文件头 `od -c`。

全部通过时退出码为 `0`，任一检查失败退出码为 `1`，并打印失败项。脚本可重复运行，不修改任何文件。

## 7. manifest 字段说明

顶层结构：

| 字段 | 类型 | 含义 |
|---|---|---|
| `version` | number | 清单格式版本，当前为 1 |
| `description` | string | 清单用途与路径基准说明 |
| `samples` | array | 样本记录数组，每项对应一个 `.epub` |

每条样本记录：

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | string | 稳定标识，用于测试用例引用，不随文件名变化 |
| `file` | string | 文件名，**相对 `test_corpus/` 目录** |
| `title` | string | 书名，与 OPF 中的 `dc:title` 一致 |
| `language` | string | 语言标签，均为 `zh-CN` |
| `source` | string | 内容来源说明 |
| `license` | string | 许可；破损样本固定为「自建测试样本」 |
| `features` | array | 覆盖特性标签，供按能力筛选样本 |
| `sha256` | string | 整个 `.epub` 文件的 SHA-256（64 位小写十六进制） |
| `size_bytes` | number | 文件字节数 |

## 8. 覆盖范围与后续

当前 6 个样本满足 P0-06 的最低要求，覆盖导入主路径、常见样式、表格与图片、EPUB2 目录、破损资源以及中文竖排。它们**不是**《技术方案》§45.3 所列 15 组样本的全集，以下能力尚未入库，后续按需补充：

- 内嵌字体与 normal/bold/700 字重；
- 浮动绕排、图跨页、全屏图页；
- 20 万字超长单章与 200 张图的性能样本；
- 缺 OPF、非 ZIP、大小写路径错误等更极端的破损书；
- 固定版式（应识别为非流式并提示）。

新增样本时，请同步更新 `build_epubs.py`、`manifest.json` 与本文档，并保证 `verify_epubs.sh` 仍然通过。
