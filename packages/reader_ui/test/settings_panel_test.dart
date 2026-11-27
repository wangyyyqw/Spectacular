import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/tap_zones.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('主题面板仅显示 $brightness 对应色块且不显示主题名称', (tester) async {
      final changes = <String>[];
      final current = brightness == Brightness.dark
          ? ReaderTheme.black
          : ReaderTheme.white;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SettingsPanel(
              section: SettingsSection.theme,
              overrides: ReaderSettingsDefaults.overrides,
              themeId: current.id,
              onOverridesChanged: (_) {},
              onThemeChanged: changes.add,
            ),
          ),
        ),
      );
      for (final theme in ReaderTheme.themes) {
        expect(
          find.byKey(ValueKey('settings-theme-${theme.id}')),
          theme.isDark == current.isDark ? findsOneWidget : findsNothing,
        );
        expect(find.text(theme.name), findsNothing);
      }
      await tester.tap(find.byKey(ValueKey('settings-theme-${current.id}')));
      expect(changes, [current.id]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('设置面板：字号/行高/段距/边距滑块与主题切换（P4-21）', (tester) async {
    final changes = <ReaderOverrides>[];
    final themes = <String>[];
    var reset = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: changes.add,
            onThemeChanged: themes.add,
            onReset: () => reset = true,
          ),
        ),
      ),
    );

    expect(find.text('排版'), findsOneWidget);
    for (final key in <String>[
      'settings-font-size',
      'settings-line-height',
      'settings-paragraph-spacing',
      'settings-padding',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(
      find.text(ReaderSettingsDefaults.fontSize.toStringAsFixed(0)),
      findsWidgets,
    );

    // 拖字号滑块：值变化并回调。
    final slider = find.byKey(const ValueKey<String>('settings-font-size'));
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last.fontSize, greaterThan(ReaderSettingsDefaults.fontSize));

    // 点主题块切换。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-theme-sepia')),
      250,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-theme-sepia')),
    );
    await tester.pump();
    expect(themes.single, 'sepia');

    // 恢复默认。
    await tester.tap(find.byKey(const ValueKey<String>('settings-reset')));
    await tester.pump();
    expect(reset, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-font-size-value')),
      -250,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final label = tester.widget<Text>(
      find.byKey(const ValueKey<String>('settings-font-size-value')),
    );
    expect(
      label.data,
      ReaderSettingsDefaults.fontSize.toStringAsFixed(0),
      reason: '恢复默认后面板字号回到默认',
    );
  });

  testWidgets('连续排版滑块变化只提交最终值，松手立即生效', (tester) async {
    final changes = <ReaderOverrides>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.type,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: changes.add,
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );

    var slider = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('settings-font-size')),
    );
    slider.onChanged!(18);
    slider.onChanged!(20);
    slider.onChanged!(22);
    expect(changes, isEmpty, reason: '合并窗口内不启动多次整章重排');

    await tester.pump(const Duration(milliseconds: 80));
    expect(changes, hasLength(1));
    expect(changes.single.fontSize, 22);

    slider = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('settings-font-size')),
    );
    slider.onChanged!(23);
    slider.onChangeEnd!(23);
    expect(changes, hasLength(2));
    expect(changes.last.fontSize, 23);
  });

  testWidgets('外部排版更新丢弃旧滑杆提交，图片淡化更新不影响排版提交', (tester) async {
    final changes = <ReaderOverrides>[];
    Widget panel({double fontSize = 17, double opacity = 1}) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          section: SettingsSection.type,
          overrides: ReaderSettingsDefaults.overrides.copyWith(
            fontSize: fontSize,
          ),
          themeId: 'white',
          backgroundImageOpacity: opacity,
          onOverridesChanged: changes.add,
          onThemeChanged: (_) {},
        ),
      ),
    );
    final fontSize = find.byKey(const ValueKey('settings-font-size'));
    await tester.pumpWidget(panel());

    tester.widget<Slider>(fontSize).onChanged!(22);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(panel(opacity: 0.25));
    await tester.pump(const Duration(milliseconds: 40));
    expect(changes.single.fontSize, 22, reason: '图片淡化不取消待提交的排版');

    tester.widget<Slider>(fontSize).onChanged!(24);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(panel(fontSize: 18, opacity: 0.25));
    expect(tester.widget<Slider>(fontSize).value, 18);
    await tester.pump(const Duration(milliseconds: 80));
    expect(changes, hasLength(1), reason: '旧滑杆值不能覆盖外部恢复的字号');

    tester.widget<Slider>(fontSize).onChanged!(19);
    await tester.pump(const Duration(milliseconds: 80));
    expect(changes, hasLength(2));
    expect(changes.last.fontSize, 19, reason: '恢复后仍可继续调整');
  });

  testWidgets('宿主回传已提交的排版时保留同帧内更新的滑杆值', (tester) async {
    final changes = <ReaderOverrides>[];
    var overrides = ReaderSettingsDefaults.overrides;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SettingsPanel(
              section: SettingsSection.type,
              overrides: overrides,
              themeId: 'white',
              onOverridesChanged: (next) {
                changes.add(next);
                setState(() => overrides = next);
              },
              onThemeChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final fontSize = find.byKey(const ValueKey('settings-font-size'));
    final slider = tester.widget<Slider>(fontSize);
    slider.onChanged!(22);
    slider.onChangeEnd!(22);
    slider.onChanged!(23);
    await tester.pump();
    expect(tester.widget<Slider>(fontSize).value, 23, reason: '回传不使显示倒退');
    await tester.pump(const Duration(milliseconds: 80));
    expect(changes.map((next) => next.fontSize), [22, 23]);
    expect(overrides.fontSize, 23);
  });

  testWidgets('背景选择：点纸纹回调背景 id（P4-22）', (tester) async {
    final backgrounds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.theme,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            backgroundId: 'none',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onBackgroundChanged: backgrounds.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-bg-wood')));
    await tester.pump();
    expect(backgrounds.single, 'wood');
  });

  testWidgets('图片淡化默认保留原色，拖动合并提交且松手立即生效', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.reset);
    final changes = <double>[];
    final overrides = <ReaderOverrides>[];
    Widget panel({double opacity = 1, String id = 'image:test'}) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          section: SettingsSection.theme,
          overrides: ReaderSettingsDefaults.overrides,
          themeId: 'white',
          backgroundId: id,
          backgroundImageOpacity: opacity,
          onOverridesChanged: overrides.add,
          onThemeChanged: (_) {},
          onBackgroundChanged: (_) {},
          onBackgroundImageOpacityChanged: changes.add,
        ),
      ),
    );
    final fade = find.byKey(const ValueKey('settings-background-image-fade'));
    await tester.pumpWidget(panel());
    expect(tester.widget<Slider>(fade).value, 0);
    expect(find.text('0% 保留原色，100% 使用主题底色'), findsOneWidget);

    var slider = tester.widget<Slider>(fade);
    slider.onChanged!(20);
    await tester.pump(const Duration(milliseconds: 40));
    slider.onChanged!(50);
    expect(changes, isEmpty);
    await tester.pump(const Duration(milliseconds: 40));
    expect(changes, [0.5]);
    expect(find.text('50%'), findsOneWidget);

    slider = tester.widget<Slider>(fade);
    slider.onChanged!(100);
    slider.onChangeEnd!(100);
    await tester.pump();
    expect(changes, [0.5, 0]);
    expect(find.text('100%'), findsOneWidget);
    expect(overrides, isEmpty, reason: '图片淡化不进入排版覆盖');

    await tester.pumpWidget(panel(opacity: 0.25));
    expect(tester.widget<Slider>(fade).value, 75, reason: '恢复保存值同步到滑杆');
    for (final id in ['none', 'paper']) {
      await tester.pumpWidget(panel(opacity: 0.25, id: id));
      expect(fade, findsNothing, reason: '纯色和内置纹理不受图片淡化影响');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('外部图片淡化更新丢弃旧滑杆提交，排版更新不影响图片淡化提交', (tester) async {
    final changes = <double>[];
    Widget panel({double fontSize = 17, double opacity = 1}) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          section: SettingsSection.theme,
          overrides: ReaderSettingsDefaults.overrides.copyWith(
            fontSize: fontSize,
          ),
          themeId: 'white',
          backgroundId: 'image:test',
          backgroundImageOpacity: opacity,
          onOverridesChanged: (_) {},
          onThemeChanged: (_) {},
          onBackgroundChanged: (_) {},
          onBackgroundImageOpacityChanged: changes.add,
        ),
      ),
    );
    final fade = find.byKey(const ValueKey('settings-background-image-fade'));
    await tester.pumpWidget(panel());

    tester.widget<Slider>(fade).onChanged!(50);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(panel(fontSize: 18));
    await tester.pump(const Duration(milliseconds: 40));
    expect(changes, [0.5], reason: '排版更新不取消待提交的图片淡化');

    tester.widget<Slider>(fade).onChanged!(60);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(panel(fontSize: 18, opacity: 0.25));
    expect(tester.widget<Slider>(fade).value, 75);
    await tester.pump(const Duration(milliseconds: 80));
    expect(changes, [0.5], reason: '旧滑杆值不能覆盖外部恢复的图片淡化');

    tester.widget<Slider>(fade).onChanged!(80);
    await tester.pump(const Duration(milliseconds: 80));
    expect(changes, [0.5, 0.2], reason: '恢复后仍可继续调整');
  });

  testWidgets('宿主回传已提交的图片淡化时保留同帧内更新的滑杆值', (tester) async {
    final changes = <double>[];
    var opacity = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SettingsPanel(
              section: SettingsSection.theme,
              overrides: ReaderSettingsDefaults.overrides,
              themeId: 'white',
              backgroundId: 'image:test',
              backgroundImageOpacity: opacity,
              onOverridesChanged: (_) {},
              onThemeChanged: (_) {},
              onBackgroundChanged: (_) {},
              onBackgroundImageOpacityChanged: (next) {
                changes.add(next);
                setState(() => opacity = next);
              },
            ),
          ),
        ),
      ),
    );
    final fade = find.byKey(const ValueKey('settings-background-image-fade'));
    final slider = tester.widget<Slider>(fade);
    slider.onChanged!(50);
    slider.onChangeEnd!(50);
    slider.onChanged!(60);
    await tester.pump();
    expect(tester.widget<Slider>(fade).value, 60, reason: '回传不使显示倒退');
    await tester.pump(const Duration(milliseconds: 80));
    expect(changes, [0.5, 0.4]);
    expect(opacity, 0.4);
  });

  testWidgets('墨水屏模式禁用主题与背景选择', (tester) async {
    final themes = <String>[];
    final backgrounds = <String>[];
    final opacities = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.theme,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            backgroundId: 'image:test',
            inkMode: true,
            onOverridesChanged: (_) {},
            onThemeChanged: themes.add,
            onBackgroundChanged: backgrounds.add,
            onBackgroundImageOpacityChanged: opacities.add,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('settings-ink-theme-hint')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('settings-title')))
          .data,
      '主题',
    );
    for (final key in <String>['settings-theme-sepia', 'settings-bg-wood']) {
      expect(
        tester.widget<InkWell>(find.byKey(ValueKey<String>(key))).onTap,
        isNull,
      );
    }
    expect(themes, isEmpty);
    expect(backgrounds, isEmpty);
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('settings-background-image-fade')),
          )
          .onChanged,
      isNull,
    );
    expect(opacities, isEmpty);
  });

  testWidgets('内置字体仅提供宋体，可恢复书籍字体', (tester) async {
    final changes = <ReaderOverrides>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.type,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: changes.add,
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-font-picker')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-font-hei')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('settings-font-song')));
    await tester.pumpAndSettle();

    expect(changes.single.fontFamily, FontFamilyAliases.song);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-font-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-font-book')));
    await tester.pumpAndSettle();
    expect(changes.last.fontFamily, isNull);
  });

  testWidgets('设置面板支持返回按钮', (tester) async {
    var back = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            overrides: ReaderSettingsDefaults.overrides,
            themeId: ReaderTheme.pink.id,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onBack: () => back = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-back')));
    expect(back, isTrue);
    // 当前主题高亮（pink 选中）。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-theme-pink')),
      250,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-theme-pink')),
      findsOneWidget,
    );
  });

  testWidgets('设置段可打开九宫格点击区域编辑页', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onOpenTapZoneEditor: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-tap-zones')));
    expect(opened, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('settings-title')))
          .data,
      '设置',
    );
  });

  testWidgets('注释与翻页入口等宽并排，分别选择不会修改另一项', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 720);
    addTearDown(tester.view.reset);
    ReaderFootnoteStyle? footnote;
    PageTurnMode? mode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onFootnoteStyleChanged: (value) => footnote = value,
            onPageTurnModeChanged: (value) => mode = value,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );
    final noteEntry = find.byKey(const ValueKey('settings-footnote-style'));
    final modeEntry = find.byKey(const ValueKey('settings-page-turn'));
    final noteRect = tester.getRect(noteEntry);
    final modeRect = tester.getRect(modeEntry);
    expect(noteRect.top, modeRect.top);
    expect(noteRect.size, modeRect.size);
    expect(noteRect.height, 52);
    expect(noteRect.right, lessThan(modeRect.left));
    await tester.tap(noteEntry);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<PageTurnMode>), findsNothing);
    final paper = find.byKey(const ValueKey('settings-footnote-style-paper'));
    final noteMenu = find
        .ancestor(of: paper, matching: find.byType(Material))
        .first;
    expect(tester.getRect(noteMenu).right, closeTo(noteRect.right, .01));
    await tester.tap(paper);
    await tester.pumpAndSettle();
    expect(footnote, ReaderFootnoteStyle.paper);
    expect(mode, isNull);
    await tester.tap(modeEntry);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<ReaderFootnoteStyle>), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-page-turn-none')));
    await tester.pumpAndSettle();
    expect(mode, PageTurnMode.none);
    expect(footnote, ReaderFootnoteStyle.paper);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置段使用单行翻页入口，窄屏菜单可选择全部模式', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.reset);
    final changes = <PageTurnMode>[];
    var mode = PageTurnMode.cover;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SettingsPanel(
              section: SettingsSection.settings,
              overrides: ReaderSettingsDefaults.overrides,
              themeId: 'white',
              pageTurnMode: mode,
              onPageTurnModeChanged: (value) {
                changes.add(value);
                setState(() => mode = value);
              },
              onOpenMarkSettings: () {},
              onOverridesChanged: (_) {},
              onThemeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    for (final title in ['划线设置', '翻页方式', '边角信息']) {
      expect(find.text(title), findsOneWidget);
    }
    final entry = find.byKey(const ValueKey('settings-page-turn'));
    expect(
      find.descendant(of: entry, matching: find.text('覆盖')),
      findsOneWidget,
    );
    expect(find.byType(PopupMenuItem<PageTurnMode>), findsNothing);
    const choices = {
      '堆叠': PageTurnMode.coverStack,
      '覆盖': PageTurnMode.cover,
      '仿真': PageTurnMode.simulationBessel,
      '3D': PageTurnMode.simulation3d,
      '接续': PageTurnMode.continuation,
      '滚动': PageTurnMode.scroll,
      '滑动': PageTurnMode.slideHorizontal,
      '无': PageTurnMode.none,
    };
    for (final choice in choices.entries) {
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<PopupMenuItem<PageTurnMode>>(
              find.byType(PopupMenuItem<PageTurnMode>),
            )
            .map((item) => item.value),
        orderedEquals(choices.values),
      );
      final option = find.byKey(
        ValueKey<String>('settings-page-turn-${choice.value.id}'),
      );
      await tester.ensureVisible(option);
      expect(
        find.descendant(of: option, matching: find.text(choice.key)),
        findsOneWidget,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<PageTurnMode>), findsNothing);
      expect(
        find.descendant(of: entry, matching: find.text(choice.key)),
        findsOneWidget,
      );
    }
    expect(changes, orderedEquals(choices.values));
    expect(tester.takeException(), isNull);
  });

  testWidgets('翻页菜单点击空白或系统返回关闭，未提供回调时入口禁用', (tester) async {
    final changes = <PageTurnMode>[];
    Widget panel({bool enabled = true}) => MaterialApp(
      home: Scaffold(
        body: SettingsPanel(
          section: SettingsSection.settings,
          overrides: ReaderSettingsDefaults.overrides,
          themeId: 'white',
          onPageTurnModeChanged: enabled ? changes.add : null,
          onOverridesChanged: (_) {},
          onThemeChanged: (_) {},
        ),
      ),
    );
    final entry = find.byKey(const ValueKey('settings-page-turn'));
    await tester.pumpWidget(panel());
    for (final back in [false, true]) {
      await tester.tap(entry);
      await tester.pumpAndSettle();
      if (back) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(8, 8));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<PageTurnMode>), findsNothing);
      expect(
        find.descendant(of: entry, matching: find.text('覆盖')),
        findsOneWidget,
      );
      expect(changes, isEmpty);
    }
    await tester.pumpWidget(panel(enabled: false));
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<PageTurnMode>), findsNothing);
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final screen in [const Size(320, 480), const Size(854, 384)]) {
    testWidgets('$screen 大字号翻页菜单避开安全区并可滚动选择末项', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = screen
        ..padding = const FakeViewPadding(top: 24, bottom: 20)
        ..viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(tester.view.reset);
      PageTurnMode? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 180,
                child: SettingsPanel(
                  section: SettingsSection.settings,
                  overrides: ReaderSettingsDefaults.overrides,
                  themeId: 'white',
                  onFootnoteStyleChanged: (_) {},
                  onPageTurnModeChanged: (value) => selected = value,
                  onOverridesChanged: (_) {},
                  onThemeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final entry = find.byKey(const ValueKey('settings-page-turn'));
      final noteEntry = find.byKey(const ValueKey('settings-footnote-style'));
      expect(tester.getRect(entry).top, tester.getRect(noteEntry).top);
      expect(tester.getRect(entry).bottom, lessThanOrEqualTo(screen.height));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('settings-page-turn-none'));
      final menu = find
          .ancestor(of: option, matching: find.byType(Material))
          .first;
      final rect = tester.getRect(menu);
      expect(rect.right, closeTo(tester.getRect(entry).right, .01));
      expect(rect.top, greaterThanOrEqualTo(32));
      expect(rect.bottom, lessThanOrEqualTo(screen.height - 28));
      expect(
        find.descendant(
          of: menu,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(selected, PageTurnMode.none);
      expect(find.byType(PopupMenuItem<PageTurnMode>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('设置段可切换全屏点击、屏幕常亮和音量键翻页', (tester) async {
    ReaderTapZones? zones;
    bool? keepScreenOn;
    bool? volumeKeyPaging;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onTapZonesChanged: (value) => zones = value,
            onKeepScreenOnChanged: (value) => keepScreenOn = value,
            onVolumeKeyPagingChanged: (value) => volumeKeyPaging = value,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-fullscreen-next')),
    );
    expect(zones, ReaderTapZones.fullScreenNext);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-keep-screen-on')),
    );
    expect(keepScreenOn, isTrue);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-volume-key-paging')),
    );
    expect(volumeKeyPaging, isTrue);
  });
}
