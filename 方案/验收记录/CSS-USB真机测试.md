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
