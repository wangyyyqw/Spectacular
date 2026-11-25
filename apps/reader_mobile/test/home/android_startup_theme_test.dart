import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/theme/app_theme.dart';

const _resources = 'android/app/src/main/res';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧版 Android 启动背景显示应用图标，不再是纯色占位', () {
    for (final folder in ['drawable', 'drawable-v21']) {
      final xml = File('$_resources/$folder/launch_background.xml')
          .readAsStringSync();
      expect(xml, contains('@color/startup_background'));
      expect(xml, contains('@drawable/startup_logo'));
      expect(xml, isNot(contains('@android:color/white')));
    }
    expect(
      File('$_resources/drawable-xxxhdpi/startup_logo.png').lengthSync(),
      greaterThan(0),
    );
  });

  test('原生启动与普通窗口的明暗背景和 Flutter 开屏一致', () {
    for (final entry in {
      'values': Brightness.light,
      'values-night': Brightness.dark,
    }.entries) {
      final background = buildAppTheme(brightness: entry.value)
          .scaffoldBackgroundColor
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase();
      final xml = File('$_resources/${entry.key}/colors.xml')
          .readAsStringSync();
      expect(xml, contains('name="startup_background">#$background<'));
    }
    for (final folder in [
      'values',
      'values-night',
      'values-v27',
      'values-night-v27',
    ]) {
      final xml = File('$_resources/$folder/styles.xml').readAsStringSync();
      expect(
        xml,
        contains('android:windowBackground">@color/startup_background'),
      );
    }
  });

  test('Android 12 明暗启动主题均显式配置背景与未裁切的应用标识', () {
    for (final folder in ['values-v31', 'values-night-v31']) {
      final xml = File('$_resources/$folder/styles.xml').readAsStringSync();
      expect(
        xml,
        contains(
          'android:windowSplashScreenBackground">@color/startup_background',
        ),
      );
      expect(
        xml,
        contains(
          'android:windowSplashScreenAnimatedIcon">@drawable/startup_splash_icon',
        ),
      );
      expect(
        xml,
        contains('android:windowLayoutInDisplayCutoutMode">shortEdges'),
      );
    }
    final icon = File('$_resources/drawable/startup_splash_icon.xml')
        .readAsStringSync();
    expect(icon, contains('@drawable/startup_logo'));
    for (final side in ['Left', 'Top', 'Right', 'Bottom']) {
      expect(icon, contains('android:inset$side="100dp"'));
    }
  });
}
