# S6 FTS5 可用性实验结果（桌面部分）

> 实验日期：2026-10-22　执行人：Lead
> 对应方案：§15 / §79.6，落点 §66.7
> 状态：**桌面部分完成；Android/iOS 真机未测，P0-10 尚未完成。**

## 1. 结论（仅 macOS 桌面）

- macOS 系统 `sqlite3` 3.51.0 编译进了 FTS5：`CREATE VIRTUAL TABLE ... USING fts5` 成功。
- 默认 `unicode61` 分词器**不切分中文**：`MATCH '中文'` 无结果，`MATCH 'hello'` 有结果。
- `trigram` 分词器可用：三字查询 `MATCH '中文检'` 命中；两字查询 `MATCH '中文'` 不命中（trigram 需要至少 3 个字符）。
- 对实现的直接影响：搜索索引不能依赖默认分词器切中文；技术方案 §66 的 2-gram 方案需要自建索引表（或使用 trigram + 前缀策略），这也解释了为什么 §66.7 准备了降级路径。
- Android/iOS 上的 FTS5 是否可用仍必须真机验证（P0-10 验收要求），当前无设备。

## 2. 环境

| 项 | 值 |
|---|---|
| 平台 | macOS 26.7.1 |
| SQLite | 3.51.0（系统自带 `/usr/bin/sqlite3`） |
| 命令 | `sqlite3 :memory:` + FTS5 DDL / MATCH |

## 3. 复现

```bash
sqlite3 :memory: <<'SQL'
CREATE VIRTUAL TABLE t USING fts5(x, tokenize='trigram');
INSERT INTO t VALUES('中文检索测试 hello');
SELECT 'trigram3=' || x FROM t WHERE t MATCH '中文检';
SQL
```

期望输出：`trigram3=中文检索测试 hello`。

## 4. 待办

- Android 与 iOS 真机上用 `sqlite3_flutter_libs` / drift 执行同样 DDL，确认 FTS5 与 trigram 是否编译进库。
- 若任一端不可用，按技术方案 §66.7 回退自建 2-gram 索引表。
