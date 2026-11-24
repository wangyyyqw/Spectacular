import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_book_color.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/color_cover.dart';

BookEntry _book(String id, {String? cover}) => BookEntry(
  id: id,
  title: '书籍 $id',
  author: '',
  filePath: '',
  addedAt: DateTime(2026, 11, 24),
  coverPath: cover,
);

double _hueDistance(Color first, Color second) {
  final distance =
      (HSLColor.fromColor(first).hue - HSLColor.fromColor(second).hue).abs();
  return math.min(distance, 360 - distance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('从真实封面主色生成书籍配色，日夜切换保留色相', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reading-cover-color-',
    );
    addTearDown(() => directory.delete(recursive: true));
    const red = Color(0xFFB83235);
    const blue = Color(0xFF285BAA);
    final redCover = await createColorCover(directory, 'red', red);
    final blueCover = await createColorCover(directory, 'blue', blue);
    final colors = await ReadingBookColorCache().load(
      [_book('a', cover: redCover.path), _book('b', cover: blueCover.path)],
      ['a', 'b'],
    );
    expect(_hueDistance(colors['a']!, red), lessThan(18));
    expect(_hueDistance(colors['b']!, blue), lessThan(18));
    expect(colors['a'], isNot(colors['b']));
    final night = readingBookColor(
      'a',
      brightness: Brightness.dark,
      bookColors: colors,
    );
    expect(_hueDistance(night, colors['a']!), lessThan(1));
    expect(
      night.computeLuminance(),
      greaterThan(colors['a']!.computeLuminance()),
    );
  });

  test('缺失和损坏封面不影响统计，已移出书架的书也有备用色', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reading-cover-fallback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final broken = await File('${directory.path}/broken.png')
        .writeAsBytes([0, 1, 2]);
    final cache = ReadingBookColorCache();
    for (final cover in [null, '${directory.path}/missing.png', broken.path]) {
      final colors = await cache.load([_book('a', cover: cover)], ['a']);
      expect(colors['a'], readingBookColor('a'));
    }
    final archived = await cache.load(const [], ['archived']);
    expect(archived['archived'], readingBookColor('archived'));
  });

  test('同色封面和重复备用色尽量区分，书籍顺序变化不重新分配颜色', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reading-cover-distinct-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cover = await createColorCover(
      directory,
      'same',
      const Color(0xFF417786),
    );
    final books = [
      for (var index = 0; index < 32; index++)
        _book('book-$index', cover: cover.path),
    ];
    final cache = ReadingBookColorCache();
    final colors = await cache.load(books, books.map((book) => book.id));
    expect(colors.values.toSet(), hasLength(books.length));
    expect(
      await cache.load(books.reversed, books.reversed.map((book) => book.id)),
      colors,
    );
    final fallback = await cache.load(const [], [
      for (var index = 0; index < 12; index++) 'fallback-$index',
    ]);
    expect(fallback.values.toSet(), hasLength(12));
  });

  test('更换封面路径后重新取色，旧封面结果只用于原路径', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reading-cover-change-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final first = await createColorCover(
      directory,
      'first',
      const Color(0xFFB83235),
    );
    final next = await createColorCover(
      directory,
      'next',
      const Color(0xFF28795B),
    );
    final cache = ReadingBookColorCache();
    final before = await cache.load([_book('a', cover: first.path)], ['a']);
    final after = await cache.load([_book('a', cover: next.path)], ['a']);
    expect(_hueDistance(after['a']!, before['a']!), greaterThan(60));
    expect(await cache.load([_book('a', cover: first.path)], ['a']), before);
  });
}
