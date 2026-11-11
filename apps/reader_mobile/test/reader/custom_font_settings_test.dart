import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';

void main() {
  test('四角设置持久化，修改字体、主题和边距不丢失显示偏好', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    const info = ReaderCornerInfo(
      topLeft: ReaderCornerContent.bookTitle,
      bottomRight: ReaderCornerContent.battery,
    );
    final settings = ReaderSettings.defaults
        .copyWithCornerInfo(info)
        .copyWithFont(null)
        .copyWithTheme('black')
        .copyWithOverrides(ReaderSettings.defaults.overrides);
    await store.save(settings);
    expect((await store.load()).cornerInfo, info);
    await library.setSetting(ReaderSettingsStore.keyCornerInfo, 'bad-json');
    expect((await store.load()).cornerInfo, ReaderCornerInfo.defaults);
  });

  test('自定义字体与强制开关持久化，修改其它设置不会丢失', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    final family = 'user_${List.filled(64, 'a').join()}';
    final settings =
        ReaderSettings(fontFamily: family, overrideEmbeddedFonts: true)
            .copyWithTheme('black')
            .copyWithBackground('paper')
            .copyWithInkMode(true)
            .copyWithMargins(
              const ReaderMargins(
                left: 10,
                right: 12,
                topInner: 14,
                topOuter: 0,
                bottomInner: 16,
                bottomOuter: 0,
              ),
            )
            .copyWithPageTurnMode(PageTurnMode.cover);
    await store.save(settings);
    final restored = await store.load();
    expect(restored, settings);
    expect(restored.overrides.overrideEmbeddedFonts, isTrue);
    expect(restored.copyWithOverrides(restored.overrides).fontFamily, family);
    expect(restored.copyWithFont(null).backgroundId, 'paper');
    expect(restored.copyWithFont(null).fontFamily, isNull);
    await library.setSetting(
      ReaderSettingsStore.keyFontFamily,
      'user_../../bad',
    );
    expect((await store.load()).fontFamily, isNull);
  });
}
