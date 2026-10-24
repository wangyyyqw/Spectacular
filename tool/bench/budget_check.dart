import 'dart:io';

/// 性能预算检查（P2-28）。
///
/// 在 packages/reader_core 下运行 test/bench/budget_test.dart，解析 BUDGET 行，
/// 把结果写入方案/验收记录/性能基线.md；测试失败（超预算）时退出码非 0。
///
/// 用法：
///   dart tool/bench/budget_check.dart
///   BUDGET_PAGE_BUILD_MS=0.001 dart tool/bench/budget_check.dart   # 验证失败路径
Future<void> main(List<String> args) async {
  final repoRoot = File.fromUri(Platform.script).parent.parent.parent;
  final packageDir = Directory('${repoRoot.path}/packages/reader_core');
  if (!packageDir.existsSync()) {
    stderr.writeln('找不到 packages/reader_core：${packageDir.path}');
    exit(2);
  }

  final result = await Process.run(
    'flutter',
    <String>['test', 'test/bench/budget_test.dart', '-r', 'expanded'],
    workingDirectory: packageDir.path,
    runInShell: true,
    environment: <String, String>{...Platform.environment, 'BUDGET_RUN': '1'},
  );
  final output = '${result.stdout}\n${result.stderr}';
  stdout.write(output);

  final match = RegExp(
    r'BUDGET page_build_ms=([\d.]+) cache_hit_ms=([\d.]+) '
    r'first_paint_ms=([\d.]+) page_budget_ms=([\d.]+) '
    r'hit_budget_ms=([\d.]+) first_paint_budget_ms=([\d.]+) '
    r'pass=(true|false)',
  ).firstMatch(output);
  if (match == null) {
    stderr.writeln('未找到 BUDGET 结果行，预算检查失败');
    exit(2);
  }

  final pageBuild = double.parse(match.group(1)!);
  final cacheHit = double.parse(match.group(2)!);
  final firstPaint = double.parse(match.group(3)!);
  final pageBudget = double.parse(match.group(4)!);
  final hitBudget = double.parse(match.group(5)!);
  final firstPaintBudget = double.parse(match.group(6)!);
  final pass = match.group(7) == 'true';

  final baseline = File('${repoRoot.path}/方案/验收记录/性能基线.md');
  final stamp = DateTime.now().toIso8601String();
  final buffer = StringBuffer()
    ..writeln('# 性能预算基线（P2-28）')
    ..writeln()
    ..writeln('> 生成时间：$stamp')
    ..writeln(
      '> 环境：${Platform.operatingSystem} / Dart '
      '${Platform.version.split(' ').first}',
    )
    ..writeln('> 生成脚本：`dart tool/bench/budget_check.dart`')
    ..writeln()
    ..writeln('| 指标 | 预算 | 实测 | 结果 |')
    ..writeln('|---|---:|---:|:---:|')
    ..writeln(
      '| 单页构建（20 段） | <${pageBudget.toStringAsFixed(1)}ms | '
      '${pageBuild.toStringAsFixed(3)}ms | ${pageBuild < pageBudget ? '通过' : '超预算'} |',
    )
    ..writeln(
      '| 缓存命中 | <${hitBudget.toStringAsFixed(1)}ms | '
      '${cacheHit.toStringAsFixed(3)}ms | ${cacheHit < hitBudget ? '通过' : '超预算'} |',
    )
    ..writeln(
      '| 首屏（首章构建） | <${firstPaintBudget.toStringAsFixed(0)}ms | '
      '${firstPaint.toStringAsFixed(3)}ms | '
      '${firstPaint < firstPaintBudget ? '通过' : '超预算'} |',
    )
    ..writeln()
    ..writeln('整体结果：**${pass ? '通过' : '超预算'}**');
  baseline.parent.createSync(recursive: true);
  baseline.writeAsStringSync(buffer.toString());

  stdout.writeln('基线已写入 ${baseline.path}');
  if (!pass || result.exitCode != 0) {
    stdout.writeln('性能预算未通过');
    exit(1);
  }
  stdout.writeln('性能预算通过');
}
