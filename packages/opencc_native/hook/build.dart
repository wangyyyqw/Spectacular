import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    const vendor = 'vendor/opencc';
    final sources = <String>['src/opencc_bridge.cpp'];
    for (final directory in ['$vendor/src', '$vendor/deps/marisa-0.3.1/lib']) {
      await for (final file in Directory.fromUri(
        input.packageRoot.resolve('$directory/'),
      ).list(recursive: true)) {
        if (file is! File) continue;
        if (!file.path.endsWith('.cpp') && !file.path.endsWith('.cc')) continue;
        sources.add(file.uri.toFilePath());
      }
    }
    await CBuilder.library(
      name: 'spectacular_opencc',
      assetName: 'opencc_native.dart',
      sources: sources..sort(),
      includes: [
        '$vendor/src',
        '$vendor/deps/marisa-0.3.1/include',
        '$vendor/deps/marisa-0.3.1/lib',
        '$vendor/deps/rapidjson-1.1.0',
        '$vendor/deps/darts-clone-0.32h/include',
      ],
      language: Language.cpp,
      // Android APK 不携带 libc++_shared.so，静态链接避免运行时缺库。
      cppLinkStdLib: input.config.code.targetOS == OS.android
          ? 'c++_static'
          : null,
      std: 'c++17',
      defines: {
        'Opencc_BUILT_AS_STATIC': null,
        'OPENCC_VERSION': '"1.4.2"',
        'PKGDATADIR': '""',
        'OPENCC_SEGMENTATION_PLUGIN_DIR': '""',
      },
      // Android 的 libm 与 libc 分离，静态 libc++ 不会自动带上。
      libraries: [
        if (input.config.code.targetOS == OS.android) ...['dl', 'm'],
      ],
    ).run(input: input, output: output);
  });
}
