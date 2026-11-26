# Android 构建兼容补丁

- 来源：<https://pub.dev/packages/flutter_inappwebview_android/versions/1.1.3>。
- 保留上游 `LICENSE`（Apache-2.0），源码来自已发布的 1.1.3 包。
- 本地修改：`android/build.gradle` 的两个默认 ProGuard 文件改用 `proguard-android-optimize.txt`，适配项目现有 AGP 9.1.0；不修改 WebView 运行逻辑。
- 保留构建所需 Android/Dart 源码及上游说明；未复制测试、示例和缓存。
