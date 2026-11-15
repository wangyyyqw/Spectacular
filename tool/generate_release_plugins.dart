import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/flutter_plugins.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/project.dart';

/// 使用当前本地 Flutter SDK 的正式入口生成 Release 插件注册。
Future<void> main(List<String> args) async {
  Cache.flutterRoot = args.single;
  await runInContext(
    () async {
      await injectPlugins(
        FlutterProject.current(),
        releaseMode: true,
        androidPlatform: true,
      );
      print('正式 Android 插件注册文件已重新生成。');
    },
    overrides: {TemplateRenderer: () => const MustacheTemplateRenderer()},
  );
}
