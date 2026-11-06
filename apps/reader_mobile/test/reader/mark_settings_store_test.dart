import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/mark_settings.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/tap_zones.dart';

void main() {
  test('划线设置五个键往返，首次黄色实线与标准线宽', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    final defaults = (await store.load()).markSettings;
    expect(defaults.lastColor, defaultHighlightColor);
    expect(defaults.lastStyle, ReaderAnnotationStyle.underline);
    expect(defaults.strokeWidth, 1.8);
    const mark = ReaderMarkSettings(
      lastColor: 0xff123456,
      lastStyle: ReaderAnnotationStyle.doubleUnderline,
      strokeWidth: 2.6,
      joinBackgroundLines: true,
      customColors: [0xff112233, 0xffaabbcc],
    );
    await store.save(ReaderSettings.defaults.copyWithMarkSettings(mark));
    expect((await store.load()).markSettings, mark);
    expect(await library.getSetting(ReaderSettingsStore.keyMarkLastStyle), '6');
    expect(
      await library.getSetting(ReaderSettingsStore.keyMarkCustomColors),
      '[4279312947,4289379276]',
    );
  });

  test('非法值回默认，自定义颜色过滤去重并限制八个', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    await library.setSetting(ReaderSettingsStore.keyMarkLastColor, '-1');
    await library.setSetting(ReaderSettingsStore.keyMarkLastStyle, '99');
    await library.setSetting(ReaderSettingsStore.keyMarkStrokeWidth, 'NaN');
    await library.setSetting(
      ReaderSettingsStore.keyMarkCustomColors,
      '[-1,"bad",1,1,2,3,4,5,6,7,8,9,4294967296]',
    );
    final mark = (await store.load()).markSettings;
    expect(mark.lastColor, defaultHighlightColor);
    expect(mark.lastStyle, ReaderAnnotationStyle.underline);
    expect(mark.strokeWidth, 1.8);
    expect(mark.customColors, [1, 2, 3, 4, 5, 6, 7, 8]);
    await library.setSetting(ReaderSettingsStore.keyMarkCustomColors, '{bad');
    expect((await store.load()).markSettings.customColors, isEmpty);
  });

  test('全部设置复制路径保留划线偏好', () {
    const mark = ReaderMarkSettings(
      lastStyle: ReaderAnnotationStyle.lineThrough,
      strokeWidth: 1,
      joinBackgroundLines: true,
      customColors: [0xff123456],
    );
    final original = ReaderSettings.defaults.copyWithMarkSettings(mark);
    final copies = [
      original.copyWithOverrides(original.overrides),
      original.copyWithFont(null),
      original.copyWithTheme('black'),
      original.copyWithBackground('none'),
      original.copyWithInkMode(true),
      original.copyWithMargins(ReaderMargins.defaults()),
      original.copyWithTapZones(ReaderTapZones.defaults),
      original.copyWithPageTurnMode(PageTurnMode.scroll),
      original.copyWithKeepScreenOn(true),
      original.copyWithVolumeKeyPaging(true),
    ];
    expect(copies.every((settings) => settings.markSettings == mark), isTrue);
  });
}
