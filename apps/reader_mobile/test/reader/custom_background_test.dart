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
  test('自定义主题与图片设置往返，切内置仍保留自定义', () async {
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
    expect(loaded.customTheme!.id, custom.id);
    expect(loaded.backgroundId, 'image:/test.png');
    expect(loaded.themeId, 'black');
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
  });
}
