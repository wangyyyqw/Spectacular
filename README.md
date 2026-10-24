# Spectacular Reader

Flutter 原生 EPUB 阅读器，正文渲染不使用 WebView。技术方案见 [方案/技术方案.md](方案/技术方案.md)，开发任务见 [方案/开发方案.md](方案/开发方案.md)。

## 开发阅读路径（推荐顺序）

如果你是第一次进入仓库，建议按下面顺序快速读：

1. 先读本页：了解仓库边界、常用命令和约束。
2. 再读 [方案/技术方案.md](方案/技术方案.md)：确认设计目标、架构边界和各模块职责。
3. 然后看 [方案/开发方案.md](方案/开发方案.md)：把大设计拆成阶段任务和验收标准。
4. 执行阶段任务时，进入对应的 [方案/开发方案](方案/开发方案) 子文件，按复选框逐项推进。
5. 完成后补充验收记录与交接文档：见 [方案/交接文档.md](方案/交接文档.md) 和 [方案/验收记录](方案/验收记录)。
6. 涉及 Reeden 素材时，先读 [docs/开发约定.md](docs/开发约定.md) §6.1「Reeden 资料引用纪律」与 [方案/技术方案.md](方案/技术方案.md) §2.2 证据索引，报告在 [参考/reeden/reports/](参考/reeden/reports/)；增强类任务在 [方案/开发方案/P7-Reeden增强补充.md](方案/开发方案/P7-Reeden增强补充.md)。

这条路径能把“为什么做/怎么做/怎么验收”三件事串起来，减少来回翻文档造成的上下文切换。

## 仓库结构

```
packages/reader_core/   EPUB 解析、样式、布局、绘制、位置（禁止平台插件依赖）
packages/reader_ui/     阅读视图、手势、翻页动画与面板
apps/reader_mobile/     iOS / Android / macOS 壳：文件、存储、TTS
方案/                   技术方案、开发方案（按阶段拆分）、验收记录模板
方案/spike/             已完成的技术实验
tool/                   统一脚本与进度维护
test_corpus/            本地测试样本库（不入库，需自行准备）
tests/                  跨包测试与校验脚本
参考/                   参考工程与逆向分析：阅微反编译（架构骨架）、reeden/（2.0.0 排版引擎规格报告，只借结论不复制代码）
```

## 常用命令

```bash
# 全仓库：pub get + analyze + test
bash tool/run_all.sh

# 单包
cd packages/reader_core && flutter pub get && flutter analyze && flutter test

# 运行移动端壳（macOS 桌面可直接预览）
cd apps/reader_mobile && flutter run -d macos
```

## 阅读与提交门禁

- `reader_core` 不得依赖平台插件与宿主包，由 `tool/check_core_boundary.sh` 在 CI 强制。
- 任务进度以《开发方案》阶段文件中的复选框为准，勾选后运行 `perl tool/render_plan.pl` 同步总览。
- 提交前至少执行：
  - `bash tool/run_all.sh`
  - `bash tool/check_core_boundary.sh`
  - `bash tests/analysis/verify_strict_flags.sh`
  - `bash tests/tool/verify_core_boundary.sh`
- 交接记录见 [方案/交接文档.md](方案/交接文档.md)。

## 适合的阅读方式

- 只想理解架构：看 [README.md](README.md) → [方案/技术方案.md](方案/技术方案.md)
- 只想推进实现：看 [方案/开发方案.md](方案/开发方案.md) → 对应阶段文件 → 执行测试
- 只想交付验收：看阶段任务 + 验收模板 + 交接记录，不要在实现细节中迷路

