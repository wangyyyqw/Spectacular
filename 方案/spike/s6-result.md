# S6 FTS5 可用性实验结果（iOS 模拟器 + macOS）

> 实验日期：2026-10-22（桌面）/ 2026-10-23（模拟器）　执行人：Lead
> 对应方案：§15 / §79.6，落点 §66.7
> 验收口径：经用户 2026-10-23 授权，以 iOS 模拟器 + macOS 桌面替代真机（《P0 文档》附录 A-06）。
> 状态：**完成。**

## 1. 结论

- iOS 模拟器（iPhone 18 Pro，iOS 27.0）与 macOS 上，App 内 SQLite 均为 **3.54.0**，`CREATE VIRTUAL TABLE ... USING fts5` 成功。
- 默认 `unicode61` 分词器**不切分中文**：`MATCH '中文'` 返回 0 行；`MATCH 'hello'` 返回 1 行。
- `trigram` 分词器可用：三字查询 `MATCH '中文检'` 返回 1 行；两字查询不命中（trigram 需要至少 3 个字符）。
- 对实现的直接影响：中文搜索不能依赖默认分词器；技术方案 §66 的 2-gram 自建索引仍是主路径，trigram 可作为替代或降级选项。
- Android 无 AVD/许可未接受，未测；后续真机阶段补测。

## 2. 环境与数据

| 平台 | SQLite | FTS5 | 默认分词中文 | trigram 三字 | 证据 |
|---|---|---:|---:|---:|---|
| iOS 模拟器（iPhone 18 Pro，iOS 27.0） | 3.54.0 | 可用 | 0 行 | 1 行 | `S6 platform=iOS sqlite=3.54.0 ascii=1 cjk_default=0 trigram=1` |
| macOS 26.7.1 | 3.54.0 | 可用 | 0 行 | 1 行 | `S6 platform=macOS sqlite=3.54.0 ascii=1 cjk_default=0 trigram=1` |
| Android | 未测 | — | — | — | 无 AVD、licenses 未接受 |

## 3. 复现

```bash
cd apps/reader_mobile
flutter test integration_test/s6_fts5_test.dart -d 0229CA7B-9D61-4DBA-B7DC-562DD39F9719
flutter test integration_test/s6_fts5_test.dart -d macos
```

桌面临时验证（系统 sqlite3）：

```bash
sqlite3 :memory: <<'SQL'
CREATE VIRTUAL TABLE t USING fts5(x, tokenize='trigram');
INSERT INTO t VALUES('中文检索测试 hello');
SELECT 'trigram3=' || x FROM t WHERE t MATCH '中文检';
SQL
```

## 4. 待办

- Android 真机补测 FTS5 与 trigram（P0-10 的 Android 侧）。
- 搜索实现按 §66 建 2-gram 索引；若改用 FTS5，必须显式 `tokenize='trigram'` 并处理 <3 字查询。
