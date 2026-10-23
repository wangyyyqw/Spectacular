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
SHA-256：d52b90487379be511c0e112240a749b580a1e0320a0d4ade9cd7f3e1f01ae771
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

## 5. 真机日志反馈与修复（2026-10-23）

真机：HUAWEI MRT-AL10，Android 16（SDK 36），屏幕 1272×2860，DPR 3.5，Flutter 3.47.5。

日志发现：

- `export_logs` 后出现 `export_error: Null check operator used on a null value`；
  根因是 `ReaderApp` 的 context 位于 `MaterialApp` 之上，`ScaffoldMessenger.of(context)` 找不到祖先。
- 修复：`MaterialApp` 挂 `scaffoldMessengerKey`，导出成功/失败都通过该 key 显示提示；
  导出成功新增 `export_success` 事件。
- 截图显示正文紧贴屏幕边缘；`ReaderPage` 默认增加 20px 水平、16px 垂直留白并 `ClipRect`，避免文字贴边/越界。
- 日志中 30 章翻页、跨章、返回均无 reader_error；页序连续。
- 修复后的 Release APK：`dist/spectacular-reader-release.apk`，51 MB，
  SHA-256 `d52b90487379be511c0e112240a749b580a1e0320a0d4ade9cd7f3e1f01ae771`。

## 6. 无线调试与第二轮真机验证（2026-10-23）

- 设备：MEIZU 20，Android 16（SDK 36），1080×2400，DPR 3。
- 无线调试配对/安装成功；魅族首次安装报 `INSTALL_FAILED_USER_RESTRICTED`，
  设置 `secure usb_install_item_com.spectacular.reader_mobile=1` 后安装成功。
- 真机复测：
  - 点击右上角“导出日志”，系统分享面板正常弹出，`reader_log.txt` 可发送；
  - 日志头包含机型、Android 版本、Flutter 版本、屏幕与 DPR；
  - 发现示例页固定 320×480，手机上页面下方留白；改为把 LayoutBuilder 实际内容区
    传给 `DemoChapterSource`，页面按 344×699 重新分页，正文铺满可用高度；
  - 第 1 章第 1 页显示 12 行示例文本，无空白页、无文字贴边。
- 修复后 Release APK：51 MB，
  SHA-256 `d52b90487379be511c0e112240a749b580a1e0320a0d4ade9cd7f3e1f01ae771`。
