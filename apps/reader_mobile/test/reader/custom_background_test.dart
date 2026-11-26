import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_background_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('自定义主题与图片按日夜独立往返，切回原模式仍保留自定义', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    final custom = ReaderTheme.custom(
      background: const ui.Color(0xFFEEDDBB),
      text: const ui.Color(0xFF223344),
    );
    final settings = ReaderSettings.defaults
        .copyWithTheme(custom.id)
        .copyWithBackground('image:/test.png');
    await store.save(settings);
    expect(await store.load(), settings);
    await store.save(settings.copyWithTheme('black').copyWithInkMode(true));
    final loaded = await store.load();
    expect(loaded.customTheme, isNull);
    expect(loaded.backgroundId, 'none');
    expect(loaded.themeId, 'black');
    final day = loaded.forBrightness(ui.Brightness.light);
    expect(day.customTheme!.id, custom.id);
    expect(day.backgroundId, 'image:/test.png');
  });

  test('日夜背景、淡化与配色独立保存，其他阅读设置变更保留两端', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    final day = ReaderTheme.custom(
      background: const ui.Color(0xFFEEDDBB),
      text: const ui.Color(0xFF223344),
    );
    final night = ReaderTheme.custom(
      background: const ui.Color(0xFF182530),
      text: const ui.Color(0xFFCCDDEE),
    );
    final settings = ReaderSettings.defaults
        .copyWithTheme(day.id)
        .copyWithBackground('image:/day.png')
        .copyWithBackgroundImageOpacity(0.72)
        .copyWithTheme(night.id)
        .copyWithBackground('image:/night.png')
        .copyWithBackgroundImageOpacity(0.36)
        .copyWithOverrides(
          ReaderSettings.defaults.overrides.copyWith(fontSize: 26),
        )
        .copyWithInkMode(true);
    await store.save(settings);
    final restored = await store.load();
    expect(restored, settings);
    final light = restored.forBrightness(ui.Brightness.light);
    expect(light.themeId, day.id);
    expect(light.customTheme?.id, day.id);
    expect(light.backgroundId, 'image:/day.png');
    expect(light.backgroundImageOpacity, 0.72);
    final dark = light.forBrightness(ui.Brightness.dark);
    expect(dark.themeId, night.id);
    expect(dark.customTheme?.id, night.id);
    expect(dark.backgroundId, 'image:/night.png');
    expect(dark.backgroundImageOpacity, 0.36);
    expect(dark.fontSize, 26);
    expect(dark.inkMode, isTrue);
    expect(
      dark.retainedBackgroundIds,
      containsAll(['image:/day.png', 'image:/night.png']),
    );
  });

  test('旧版单份背景只迁移到原模式，损坏的独立偏好安全回落', () async {
    final library = LibraryStore.memory();
    await library.setSetting(ReaderSettingsStore.keyThemeId, 'black');
    await library.setSetting(ReaderSettingsStore.keyBackgroundId, 'wood');
    await library.setSetting(
      ReaderSettingsStore.keyBackgroundImageOpacity,
      '0.4',
    );
    await library.setSetting(ReaderSettingsStore.keyDayBackground, '{bad');
    final restored = await ReaderSettingsStore(library).load();
    expect(restored.forBrightness(ui.Brightness.dark).backgroundId, 'wood');
    expect(restored.forBrightness(ui.Brightness.light).backgroundId, 'none');
    expect(
      restored
          .forBrightness(ui.Brightness.light)
          .forBrightness(ui.Brightness.dark)
          .backgroundImageOpacity,
      0.4,
    );
  });

  test('图片强度默认原色，持久化后恢复，旧值和非法值安全回落', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    expect((await store.load()).backgroundImageOpacity, 1);
    final settings = ReaderSettings.defaults
        .copyWithBackground('image:/test.png')
        .copyWithBackgroundImageOpacity(0.37);
    await store.save(settings);
    expect((await store.load()), settings);
    expect(settings, isNot(settings.copyWithBackgroundImageOpacity(1)));
    for (final entry in const {
      'bad': 1.0,
      'NaN': 1.0,
      '-0.4': 0.0,
      '2': 1.0,
    }.entries) {
      await library.setSetting(
        ReaderSettingsStore.keyBackgroundImageOpacity,
        entry.key,
      );
      expect((await store.load()).backgroundImageOpacity, entry.value);
    }
  });

  test('图片缩小复制、恢复与文件校验，清理避开新图片', () async {
    final directory = Directory.systemTemp.createTempSync('reader-background-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = ReaderBackgroundStore(
      directoryProvider: () async => directory,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF5599CC), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2000, 1000);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final id = await store.import(data!.buffer.asUint8List());
    final restored = ReaderBackgroundStore(
      directoryProvider: () async => directory,
    );
    final codec = await ui.instantiateImageCodec(await restored.load(id));
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1600);
    expect(frame.image.height, 800);
    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels!.getUint32(0), 0x5599CCFF, reason: '导入缩放不改变图片原色');
    frame.image.dispose();
    codec.dispose();
    await store.cleanUnused('none');
    expect(File(id.substring(6)).existsSync(), isTrue);
    await expectLater(store.load('bad'), throwsFormatException);
    await expectLater(store.load('image:/outside.png'), throwsFormatException);
    await expectLater(
      store.import(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
    await expectLater(store.import(Uint8List(0)), throwsFormatException);
    await expectLater(
      store.import(Uint8List(21 * 1024 * 1024)),
      throwsFormatException,
    );
    final old = File('${directory.path}/reader_backgrounds/background-old.png');
    await old.writeAsBytes([1]);
    await old.setLastModified(DateTime.now().subtract(const Duration(days: 2)));
    final pending = File(
      '${directory.path}/reader_backgrounds/background-pending.png',
    );
    await pending.writeAsBytes([1]);
    await pending.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    await store.cleanUnused(id, pendingId: 'image:${pending.path}');
    expect(pending.existsSync(), isTrue, reason: '尚未保存的选择不能被清理');
    expect(old.existsSync(), isFalse);
    expect(File(id.substring(6)).existsSync(), isTrue);
    await store.cleanUnused('none', retainedIds: [id, 'image:${pending.path}']);
    expect(pending.existsSync(), isTrue, reason: '另一模式的旧背景不能被清理');
  });
}
