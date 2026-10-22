# P0-16 drift 原型验收记录

> 任务：P0-16。日期：2026-10-23。执行人：Lead。
> 验收口径：经用户 2026-10-23 授权，以 iOS 模拟器 + macOS 桌面替代两端真机（《P0 文档》附录 A-06）。

## 1. 结论

**通过（iOS 模拟器 + macOS）。**

- v1 旧库（`books(id,title)`，`user_version=1`）由 v2 `PrototypeDb` 打开后自动迁移，新增 `author` 列，旧数据保留。
- 迁移后插入带作者的新书成功，共 2 行；全新内存库 `onCreate` 路径建表并读写成功。
- Android 无 AVD、licenses 未接受，未测；后续真机阶段补测。

## 2. 证据

| 平台 | 迁移行 | 迁移后总行 | 列 | 新库行 | 输出 |
|---|---:|---:|---|---:|---|
| iOS 模拟器（iPhone 18 Pro，iOS 27.0） | 1 | 2 | id, title, author | 1 | `P0-16 platform=iOS migrated_rows=1 all_rows=2 columns=[id, title, author] fresh_rows=1` |
| macOS 26.7.1 | 1 | 2 | id, title, author | 1 | `P0-16 platform=macOS migrated_rows=1 all_rows=2 columns=[id, title, author] fresh_rows=1` |

## 3. 复现

```bash
cd apps/reader_mobile
flutter test integration_test/p0_16_drift_test.dart -d 0229CA7B-9D61-4DBA-B7DC-562DD39F9719
flutter test integration_test/p0_16_drift_test.dart -d macos
```

## 4. 文件

- 库定义与迁移：`apps/reader_mobile/lib/storage/prototype_db.dart`
- 生成代码：`apps/reader_mobile/lib/storage/prototype_db.g.dart`
- 集成测试：`apps/reader_mobile/integration_test/p0_16_drift_test.dart`

## 5. 限制

- 表结构只覆盖 `books(id,title,author)`，不是技术方案 §36 的完整 schema；正式表在 P4-01 落。
- `NativeDatabase` 直接打开文件，未接入 `path_provider` 的默认路径逻辑（`openDefault` 已提供，但测试用显式临时文件以便清理）。
- 测试输出中的 debug warning 来自集成测试的环境提示，不影响断言结果。
