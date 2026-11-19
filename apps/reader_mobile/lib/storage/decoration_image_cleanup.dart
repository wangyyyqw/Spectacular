import 'dart:convert';
import 'dart:io';

import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/decorations/decoration_style.dart';

import 'db.dart';

Future<void> cleanDecorationImages(
  AppDatabase db,
  ReaderDecorationImageStore? images,
) async {
  if (images == null) return;
  await db.transaction(() async {
    final manual = await db.select(db.decorations).get();
    final rules = await db.select(db.decorationRules).get();
    final paths = <String>{};
    for (final raw in [
      ...manual.map((row) => row.styleJson),
      ...rules.map((row) => row.styleJson),
    ]) {
      try {
        final style = ReaderDecorationStyle.fromJson(jsonDecode(raw));
        if (style.backgroundImagePath case final path?) paths.add(path);
      } on FormatException {
        return;
      }
    }
    try {
      await images.removeUnused(paths);
    } on FileSystemException {
      return;
    }
  });
}
