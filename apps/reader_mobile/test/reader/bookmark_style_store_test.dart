import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_background_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/annotations/mark_settings.dart';
import 'package:reader_ui/bookmarks/bookmark_style.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/tap_zones.dart';
import 'package:reader_ui/theme/reader_margins.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('书签样式保存恢复，全部设置复制路径保留自定义外观', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    expect((await store.load()).bookmarkStyle, const ReaderBookmarkStyle());
    const style = ReaderBookmarkStyle(
      width: 40,
      length: 120,
      imageId: 'image:/bookmark.png',
    );
    const tts = ReaderTtsSettings(
      mode: ReaderTtsMode.offline,
      narratorVoiceId: 'vits-piper-zh_CN-chaowen-medium',
      dialogueSpeed: 0.9,
    );
    final settings = const ReaderSettings(
      showSystemBars: true,
      tts: tts,
    ).copyWithBookmarkStyle(style);
    await store.save(settings);
    expect(await store.load(), settings);
    for (final copy in [
      settings.copyWithOverrides(settings.overrides),
      settings.copyWithFont(null),
      settings.copyWithTheme('black'),
      settings.copyWithBackground('none'),
      settings.copyWithInkMode(true),
      settings.copyWithMargins(ReaderMargins.defaults()),
      settings.copyWithCornerInfo(ReaderCornerInfo.defaults),
      settings.copyWithTapZones(ReaderTapZones.defaults),
      settings.copyWithPageTurnMode(PageTurnMode.scroll),
      settings.copyWithKeepScreenOn(true),
      settings.copyWithVolumeKeyPaging(true),
      settings.copyWithMarkSettings(const ReaderMarkSettings()),
    ]) {
      expect(copy.bookmarkStyle, style);
      expect(copy.tts, tts);
      expect(copy.showSystemBars, isTrue);
    }
    expect(settings.copyWithShowSystemBars(false).bookmarkStyle, style);
    expect(
      settings.copyWithTts(tts.copyWith(narratorSpeed: 1.2)).bookmarkStyle,
      style,
    );
    final restored = ReaderSettings.fromOverrides(
      settings.overrides,
      themeId: settings.themeId,
      tts: settings.tts,
      showSystemBars: settings.showSystemBars,
      bookmarkStyle: settings.bookmarkStyle,
    );
    expect(restored, settings);
  });

  test('旧设置和损坏数据回默认，超范围尺寸在读取边界限制', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    await library.setSetting(ReaderSettingsStore.keyBookmarkStyle, '{bad');
    expect((await store.load()).bookmarkStyle, const ReaderBookmarkStyle());
    await library.setSetting(
      ReaderSettingsStore.keyBookmarkStyle,
      '{"width":-1,"length":9999,"imageId":3}',
    );
    expect(
      (await store.load()).bookmarkStyle,
      const ReaderBookmarkStyle(width: 12, length: 200),
    );
  });

  test('书签图片复制到独立目录，原文件移走后可恢复透明图片', () async {
    final directory = Directory.systemTemp.createTempSync('bookmark-images-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = ReaderBackgroundStore(
      directoryProvider: () async => directory,
      directoryName: 'bookmark_images',
      filePrefix: 'bookmark',
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(2, 0, 20, 40),
      ui.Paint()..color = const ui.Color(0xFF884433),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(24, 60);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final original = File('${directory.path}/local.png');
    await original.writeAsBytes(data!.buffer.asUint8List());
    final id = await store.import(await original.readAsBytes());
    await original.delete();
    expect(
      id.replaceAll(Platform.pathSeparator, '/'),
      contains('/bookmark_images/bookmark-'),
    );
    final reopened = ReaderBackgroundStore(
      directoryProvider: () async => directory,
      directoryName: 'bookmark_images',
      filePrefix: 'bookmark',
    );
    final codec = await ui.instantiateImageCodec(await reopened.load(id));
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 24);
    expect(frame.image.height, 60);
    final pixels = await frame.image.toByteData();
    expect(pixels!.getUint8(3), 0, reason: '保留透明背景');
    frame.image.dispose();
    codec.dispose();
    await expectLater(
      store.import(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });
}
