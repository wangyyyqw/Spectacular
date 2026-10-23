# 诊断日志与 APK 打包记录

> 日期：2026-10-23　范围：M0 真机验收准备（P1-34 前置）

## 1. 日志功能

新增 `apps/reader_mobile/lib/diagnostics/reader_log.dart`：

- App 启动自动初始化，写入环境头：
  - Flutter 版本（当前 3.47.5）
  - Dart / OS / OS 版本 / locale
  - 应用名、版本号、build number、包名
  - Android：厂商、机型、Android 版本、SDK；iOS：机型、系统版本
  - 屏幕物理尺寸、DPR
- 自动事件：
  - `app_start`
  - `reader_open`
  - `page_turn`（章/页 + 页首 40 字）
  - `reader_error`
  - `flutter_error` / `platform_error`
  - `export_logs` / `export_error`
- 日志文件：
  - Android/iOS 应用支持目录下 `reader_log.txt`
  - 追加写入，异常不阻塞阅读
- 导出：
  - 阅读页右上角“导出日志”按钮
  - 调起系统分享面板，分享 `reader_log.txt`
  - 按钮导出前会再记一条 `export_logs`

## 2. APK

构建命令：

```bash
cd apps/reader_mobile
flutter build apk --debug
flutter build apk --release
```

交付产物（release，已复制到本地 `dist/`）：

```
apps/reader_mobile/dist/spectacular-reader-release.apk
大小：51 MB
SHA-256：c43e9c26882acc9049c1f26c7f7cbe718d5800a477bb706283cff5e1941db16a
签名：Android Debug（仅供测试安装）
```

Debug 备选：

```
build/app/outputs/flutter-apk/app-debug.apk
大小：181 MB
SHA-256：44b65842513f6fdba74e6d1a977f806427186b6b570e5e5158629afef6887144
```

构建备注：

- debug 构建约 7～75s，release 约 36s。
- release 构建时临时移除了 `integration_test` dev 依赖，避免 Flutter 生成的 `GeneratedPluginRegistrant.java` 在 release 中引用不存在的 integration_test 插件；构建后已恢复 `pubspec.yaml`。
- 正式发布前需要配置 release 签名；当前 APK 用 Android Debug 证书，不能上架。
- APK 已包含 30 章示例阅读页、诊断日志与系统分享插件。

## 3. 真机使用步骤

1. 安装 `app-debug.apk`；
2. 打开 App，进入 30 章示例阅读页；
3. 点击左右区域或滑动翻页，跨章后返回；
4. 退出重进，检查是否恢复到上次页（当前为内存进度，进程重启会丢失，见限制）；
5. 点击右上角“导出日志”，通过系统分享发送 `reader_log.txt`；
6. 日志头包含机型、Android 版本、Flutter 版本，可直接填 P1-34 记录表。

## 4. 限制

- 进度仍为内存存储，杀进程后会丢失；P1-34 前需补磁盘持久化，或测试时避免杀进程。
- Debug APK 体积较大（约 159MB，含多 ABI）；release 包会小很多。
- 日志包含页首文本，属于阅读内容；分享前需确认用户知情。
- 日志文件位于应用私有目录，普通文件管理器不可见，必须通过“导出日志”分享。
