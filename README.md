# Spectacular Reader

Flutter 原生 EPUB 阅读器，正文渲染不使用 WebView。技术方案见 [方案/技术方案.md](方案/技术方案.md)，开发任务见 [方案/开发方案.md](方案/开发方案.md)。

## 仓库结构

```
packages/reader_core/   EPUB 解析、样式、布局、绘制、位置（禁止平台插件依赖）
packages/reader_ui/     阅读视图、手势、翻页动画与面板
apps/reader_mobile/     iOS / Android / macOS 壳：文件、存储、TTS
方案/                   技术方案、开发方案（按阶段拆分）、接受记录模板
方案/spike/             已完成的技术实验
tool/                   统一脚本与进度维护
test_corpus/            测试样本库（P0-06）
tests/                  跨包测试与校验脚本
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

## 约束

- `reader_core` 不得依赖平台插件与宿主包，由 `tool/check_core_boundary.sh` 在 CI 强制。
- 任务进度以《开发方案》阶段文件中的复选框为准，勾选后运行 `perl tool/render_plan.pl` 同步总览。
- 交接记录见 [方案/交接文档.md](方案/交接文档.md)。
