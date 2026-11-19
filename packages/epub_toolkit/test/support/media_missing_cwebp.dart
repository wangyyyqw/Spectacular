import 'dart:io';

import 'package:spectacular_epub_tools/src/features/img_to_webp/img_to_webp.dart';

Future<void> main(List<String> arguments) async {
  try {
    await ImgToWebpOperation.execute(
      epubPath: arguments[0],
      outputPath: arguments[1],
    );
    stderr.writeln('缺少 cwebp 时操作没有报错');
    exitCode = 1;
  } on StateError catch (error) {
    if (!error.message.contains('未找到可用的 cwebp') ||
        File(arguments[1]).existsSync()) {
      stderr.writeln(error);
      exitCode = 1;
    } else {
      stdout.writeln('已确认缺少 cwebp 时明确报错且未生成输出');
    }
  }
}
