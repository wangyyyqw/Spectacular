import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/dictionary/dictionary_client.dart';
import 'package:reader_mobile/dictionary/dictionary_model_picker.dart';
import 'package:reader_mobile/theme/app_theme.dart';

void main() {
  testWidgets('320dp 模型列表支持搜索、当前模型标识和选择', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('打开'),
              onPressed: () async {
                selected = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: DictionaryModelPicker(
                        currentModel: 'current-model',
                        loadModels: () async => [
                          'gpt-example',
                          'DeepSeek-example',
                          'current-model',
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('当前模型'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('dictionary-model-search')),
      'DEEPSEEK',
    );
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek-example'), findsOneWidget);
    expect(find.text('gpt-example'), findsNothing);
    await tester.tap(find.text('DeepSeek-example'));
    await tester.pumpAndSettle();
    expect(selected, 'DeepSeek-example');
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新失败保留已有模型，手填模型不在列表也可见', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionaryModelPicker(
            currentModel: 'manual',
            initialModels: const ['available'],
            loadModels: () async => throw const DictionaryException('获取超时，请重试'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前手填模型（不在返回列表中）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dictionary-model-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('available'), findsOneWidget);
    expect(find.text('获取超时，请重试'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('dictionary-model-search')),
      '不存在',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的模型，可返回手动填写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭后忽略晚到的模型列表', (tester) async {
    final pending = Completer<List<String>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionaryModelPicker(
            currentModel: '',
            loadModels: () => pending.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(['late-model']);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏与键盘展开时搜索和刷新错误不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: DictionaryModelPicker(
            currentModel: 'manual-model',
            loadModels: () async => throw const DictionaryException(
              '获取失败，请检查服务地址与网络后重试，也可返回手动填写模型名称。',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dictionary-model-search')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
