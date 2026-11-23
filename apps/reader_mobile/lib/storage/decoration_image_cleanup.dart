import 'dart:convert';
import 'dart:io';

import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/decorations/decoration_style.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';

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
        final rule = ReaderDecorationRuleStyle.fromJson(jsonDecode(raw));
        if (rule.darkStyle?.backgroundImagePath case final path?) {
          paths.add(path);
        }
      } on FormatException {
        return;
      }
    }
    final saved = await (db.select(
      db.settingsTable,
    )..where((t) => t.key.equals('decoration.styles'))).getSingleOrNull();
    if (saved != null) {
      for (final item
          in (jsonDecode(saved.value) as Map<String, Object?>).values) {
        final style = ReaderDecorationRuleStyle.fromJson(
          (item as Map<String, Object?>)['style'],
        );
        if (style.backgroundImagePath case final path?) paths.add(path);
        if (style.darkStyle?.backgroundImagePath case final path?) {
          paths.add(path);
        }
      }
    }
    try {
      await images.removeUnused(paths);
    } on FileSystemException {
      return;
    }
  });
}
