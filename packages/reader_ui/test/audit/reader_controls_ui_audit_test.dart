import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_editor_sheet.dart';
import 'package:reader_ui/annotations/note_composer_sheet.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/panels/margin_editor.dart';
import 'package:reader_ui/panels/reader_settings_sheet.dart';
import 'package:reader_ui/panels/tap_zone_editor.dart';
import 'package:reader_ui/selection/selection_menu.dart';
import 'package:reader_ui/tap_zones.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _pumpPage(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(360, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(
  WidgetTester tester,
  Widget sheet,
  ValueChanged<Object?> onResult,
) async {
  await _pumpPage(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final result = await showModalBottomSheet<Object?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => sheet,
          );
          onResult(result);
        },
        child: const Text('打开'),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void _expectSheet(WidgetTester tester, String key) {
  final material = tester.widget<Material>(_key(key));
  expect(
    material.borderRadius,
    const BorderRadius.vertical(top: Radius.circular(8)),
  );
  expect(material.clipBehavior, Clip.antiAlias);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('阅读菜单四入口可点击，夜间抽屉使用更浅的面板底色', (tester) async {
    ReaderMenuEntry? selected;
    Widget menu({Widget? drawer}) => ReaderMenuOverlay(
      open: true,
      theme: ReaderTheme.black,
      bookTitle: '一本书',
      progress: 0.4,
      chapterLabel: '第二章',
      onBack: () {},
      onToggleDayNight: () {},
      nightMode: true,
      onPreviousChapter: () {},
      onNextChapter: () {},
      onSeek: (_) {},
      onEntry: (value) => selected = value,
      drawerTitle: drawer == null ? '' : '目录',
      drawerChild: drawer,
      onCloseDrawer: () {},
    );
    await _pumpPage(tester, menu());
    for (final entry in ReaderMenuEntry.values) {
      await tester.tap(_key('menu-entry-${entry.name}'));
      expect(selected, entry);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: menu(
            drawer: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('章节内容'),
                TextButton(onPressed: () {}, child: const Text('阅读面板操作')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('章节内容'));
    expect(
      Theme.of(context).colorScheme.surface.computeLuminance(),
      greaterThan(ReaderTheme.black.background.computeLuminance()),
      reason: '夜间菜单底板应与阅读页区分',
    );
    final buttonColor = Theme.of(context).textButtonTheme.style?.foregroundColor
        ?.resolve({});
    expect(buttonColor, ReaderTheme.black.text);
    final contrast = ReaderTheme(
      id: 'controls',
      name: '控件',
      background: Theme.of(context).colorScheme.surface,
      text: buttonColor!,
    );
    expect(contrast.luminance, greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('圆角选区菜单保持复制和笔记入口', (tester) async {
    final selected = <String>[];
    await _pumpPage(
      tester,
      Stack(
        children: [
          SelectionMenu(
            anchor: const Rect.fromLTWH(20, 160, 200, 30),
            bounds: const Size(360, 720),
            actions: [
              for (final label in ['复制', '笔记'])
                SelectionAction(
                  id: label,
                  label: label,
                  onTap: () => selected.add(label),
                ),
            ],
          ),
        ],
      ),
    );
    for (final label in ['复制', '笔记']) {
      await tester.tap(_key('selection-action-$label'));
    }
    expect(selected, ['复制', '笔记']);
    final material = tester.widget<Material>(_key('selection-menu'));
    expect(material.borderRadius, BorderRadius.circular(12));
    expect(material.clipBehavior, Clip.antiAlias);
    expect(material.elevation, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主题色块变紧凑后仍能切换白色和深色主题', (tester) async {
    String? theme;
    await _pumpPage(
      tester,
      SettingsPanel(
        overrides: const ReaderOverrides(),
        themeId: 'white',
        section: SettingsSection.theme,
        onOverridesChanged: (_) {},
        onThemeChanged: (value) => theme = value,
      ),
    );
    expect(_key('settings-theme-black'), findsNothing);
    await tester.tap(_key('settings-theme-sepia'));
    expect(theme, 'sepia');
    await tester.tap(_key('settings-theme-white'));
    expect(theme, 'white');
    await _pumpPage(
      tester,
      Theme(
        data: ThemeData.dark(),
        child: SettingsPanel(
          overrides: const ReaderOverrides(),
          themeId: 'black',
          section: SettingsSection.theme,
          onOverridesChanged: (_) {},
          onThemeChanged: (value) => theme = value,
        ),
      ),
    );
    expect(_key('settings-theme-white'), findsNothing);
    await tester.tap(_key('settings-theme-black'));
    expect(theme, 'black');
    expect(tester.takeException(), isNull);
  });

  testWidgets('小圆角九宫格支持修改并保存点击区配置', (tester) async {
    ReaderTapZones? saved;
    await _pumpPage(
      tester,
      TapZoneEditor(
        zones: ReaderTapZones.defaults,
        onApply: (value) => saved = value,
        onCancel: () {},
        foreground: Colors.black,
        background: Colors.white,
      ),
    );
    await tester.tap(_key('tap-zone-center'));
    await tester.tap(_key('tap-zone-apply'));
    expect(saved?.actionAt(ReaderTapZone.center), ReaderTapAction.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('笔记弹层在小屏编辑并返回保存内容', (tester) async {
    Object? result;
    await _openSheet(
      tester,
      const ReaderNoteComposerSheet(quote: '这是一段原文'),
      (value) => result = value,
    );
    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: _key('note-composer-sheet'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.borderRadius, ReaderUiStyle.sheetRadius);
    expect(tester.takeException(), isNull);
    await tester.enterText(_key('note-composer-input'), '  我的读书笔记  ');
    await tester.pump();
    await tester.tap(_key('note-composer-save'));
    await tester.pumpAndSettle();
    expect((result! as AnnotationEditAction).note, '我的读书笔记');
    expect(tester.takeException(), isNull);
  });

  testWidgets('高亮弹层保留颜色与样式修改操作', (tester) async {
    Object? result;
    final time = DateTime(2026, 11, 4);
    await _openSheet(
      tester,
      ReaderAnnotationEditorSheet(
        annotation: ReaderAnnotation(
          id: '审计标注',
          type: ReaderAnnotationType.mark,
          startCfi: 'epubcfi(/6/2!/4/2/1:0)',
          endCfi: 'epubcfi(/6/2!/4/2/1:10)',
          quote: '标注原文',
          createdAt: time,
          updatedAt: time,
        ),
      ),
      (value) => result = value,
    );
    _expectSheet(tester, 'annotation-editor-sheet');
    await tester.tap(_key('annotation-color-0xFFA5D6A7'));
    await tester.tap(_key('annotation-style-underline'));
    await tester.pump();
    await tester.tap(_key('annotation-save-changes'));
    await tester.pumpAndSettle();
    final action = result! as AnnotationEditAction;
    expect(action.type, AnnotationEditActionType.save);
    expect(action.color, 0xFFA5D6A7);
    expect(action.style, ReaderAnnotationStyle.underline);
    expect(tester.takeException(), isNull);
  });

  testWidgets('脚注弹层显示多段文本', (tester) async {
    await _openSheet(
      tester,
      const ReaderFootnoteDialog(
        footnote: PageFootnote(
          start: 0,
          end: 1,
          label: '1',
          kind: NoteKind.footnote,
          text: '第一段脚注\n第二段脚注',
        ),
      ),
      (_) {},
    );
    _expectSheet(tester, 'reader-footnote-dialog');
    expect(find.text('第一段脚注'), findsOneWidget);
    expect(find.text('第二段脚注'), findsOneWidget);
    Navigator.of(tester.element(_key('reader-footnote-dialog'))).pop();
    await tester.pumpAndSettle();
    expect(_key('reader-footnote-dialog'), findsNothing);
  });

  testWidgets('扁平边距控件支持拖动预览与保存', (tester) async {
    final defaults = ReaderMargins.defaults();
    ReaderMargins? preview;
    ReaderMargins? saved;
    await _pumpPage(
      tester,
      MarginEditor(
        margins: defaults,
        defaults: defaults,
        onPreview: (value) => preview = value,
        onApply: (value) => saved = value,
        onCancel: () {},
      ),
    );
    await tester.drag(_key('margin-left'), const Offset(14, 0));
    await tester.pumpAndSettle();
    await tester.tap(_key('margin-apply'));
    expect(preview?.left, greaterThan(defaults.left));
    expect(saved, preview);
    expect(tester.takeException(), isNull);
  });
}
