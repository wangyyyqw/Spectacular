import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

void main() {
  testWidgets('已有懒加载列表在正常与极短窗口中都保持有限视口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final height in [220.0, 64.0]) {
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: height,
              child: ReaderSheetForm(
                title: const Text('本书笔记'),
                scrollContent: false,
                contentPadding: EdgeInsets.zero,
                content: ListView.builder(
                  key: ValueKey(height),
                  itemCount: 200,
                  itemExtent: 48,
                  itemBuilder: (_, index) {
                    built++;
                    return Text('笔记 $index');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(built, lessThan(40), reason: '保持有限视口，不一次构建全部笔记');
      expect(
        tester.getSize(find.byType(ListView)).height,
        lessThanOrEqualTo(height),
      );
      if (height == 220) {
        expect(find.byType(SingleChildScrollView), findsNothing);
      }
      await tester.ensureVisible(find.byType(ListView));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('保存错误扩大操作区后切换布局仍保留正在输入的草稿', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var failed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReaderSheetForm(
              title: const Text('编辑书评'),
              content: const TextField(
                decoration: InputDecoration(labelText: '书评内容'),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (failed)
                        const Text(
                          '保存失败：书评暂时无法写入。\n'
                          '原有内容已保留。\n'
                          '请稍后重试。\n'
                          '存储路径暂时无法访问。\n'
                          '检查设备存储空间。\n'
                          '稍后再次保存。\n'
                          '草稿保持在当前编辑框内。\n'
                          '关闭前请确认是否放弃。',
                        ),
                      FilledButton(
                        onPressed: () => setState(() => failed = true),
                        child: const Text('保存书评'),
                      ),
                      TextButton(onPressed: () {}, child: const Text('取消')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留这段书评草稿');
    await tester.tap(find.text('保存书评'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '保留这段书评草稿',
    );
    await tester.ensureVisible(find.text('保存书评'));
    await tester.pumpAndSettle();
    expect(find.text('保存书评').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final visibleHeight in [220.0, 240.0]) {
    testWidgets('可见高度$visibleHeight时长书名和保存失败操作区仍可到达', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: 520 - visibleHeight);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderDrawer<void>(
                  context: context,
                  builder: (context) => ReaderSheetForm(
                    showCloseButton: false,
                    title: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('编辑书评'),
                              SizedBox(height: 3),
                              Text('一本需要换行的长书名：在漫长的旅途中记录阅读、生活与重新出发的故事'),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    content: const TextField(
                      minLines: 4,
                      maxLines: 8,
                      decoration: InputDecoration(labelText: '书评内容'),
                    ),
                    actions: [
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text('保存失败：书评暂时无法写入，请稍后重试。原有内容已保留。'),
                            ),
                            FilledButton(
                              onPressed: () {
                                saved = true;
                                Navigator.pop(context);
                              },
                              child: const Text('保存书评'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {},
                              child: const Text('取消'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {},
                              child: const Text('删除书评'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                child: const Text('编辑已有书评'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑已有书评'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '真实书评草稿');
      await tester.ensureVisible(find.text('保存书评'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('保存书评')).bottom,
        lessThanOrEqualTo(visibleHeight),
      );
      await tester.tap(find.text('保存书评'));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('表单内容受横向约束，长内容滚动而保存和关闭保持可用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReaderDrawer<String>(
                  context: context,
                  builder: (context) => ReaderSheetForm(
                    title: const Text('编辑资料'),
                    content: SizedBox(
                      key: const ValueKey('表单内容'),
                      width: 900,
                      child: Column(
                        children: [
                          for (var i = 0; i < 30; i++) Text('实际资料第 $i 行'),
                        ],
                      ),
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(context, '已保存'),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('表单内容'))).width, 288);
    expect(find.text('保存').hitTestable(), findsOneWidget);
    expect(find.byTooltip('关闭').hitTestable(), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('实际资料第 29 行').hitTestable(), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, '已保存');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字号和键盘出现时输入与操作仍可滚动到达', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2.4)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReaderDrawer<void>(
                context: context,
                builder: (context) => ReaderSheetForm(
                  title: const Text('很长的资料编辑标题需要完整换行'),
                  content: const TextField(
                    decoration: InputDecoration(labelText: '名称'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () {
                        saved = true;
                        Navigator.pop(context);
                      },
                      child: const Text('保存资料'),
                    ),
                  ],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ReaderSheetForm)).bottom, 560);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '实际名称');
    await tester.ensureVisible(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('保存资料')).bottom, lessThanOrEqualTo(300));
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}
