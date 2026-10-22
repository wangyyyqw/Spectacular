import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S6 当前平台 SQLite 支持 FTS5 与 trigram，中文默认分词不命中', (tester) async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);

    final version = db.select('SELECT sqlite_version() AS v').first['v'];
    db.execute('CREATE VIRTUAL TABLE docs USING fts5(body)');
    db.execute("INSERT INTO docs VALUES ('中文检索测试 hello')");

    final ascii = db.select("SELECT body FROM docs WHERE docs MATCH 'hello'");
    final cjkDefault = db.select("SELECT body FROM docs WHERE docs MATCH '中文'");

    db.execute(
      "CREATE VIRTUAL TABLE docs_tri USING fts5(body, tokenize='trigram')",
    );
    db.execute("INSERT INTO docs_tri VALUES ('中文检索测试 hello')");
    final trigram = db.select(
      "SELECT body FROM docs_tri WHERE docs_tri MATCH '中文检'",
    );

    // ignore: avoid_print
    print(
      'S6 platform=${defaultTargetPlatform.name} sqlite=$version '
      'ascii=${ascii.length} cjk_default=${cjkDefault.length} '
      'trigram=${trigram.length}',
    );

    expect(ascii, isNotEmpty, reason: 'FTS5 英文匹配应可用');
    expect(cjkDefault, isEmpty, reason: '默认 unicode61 不切分中文');
    expect(trigram, isNotEmpty, reason: 'trigram 分词器应支持三字中文查询');
  });
}
