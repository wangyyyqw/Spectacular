# P0 TTS 能力探测记录

> 任务：P0-20。日期：2026-10-23。执行人：Lead。
> 验收口径：经用户 2026-10-23 授权，以 iOS 模拟器 + macOS 桌面替代两端真机（《P0 文档》附录 A-06）。

## 1. 结论

- iOS 模拟器（iPhone 18 Pro，iOS 27.0）与 macOS 上，`flutter_tts` 可枚举中文语音并完成中文朗读回调。
- 两端均支持 `zh-CN` 与 `zh-TW`；`isLanguageAvailable('zh-CN')` 为 true。
- 语速参数 0.1 / 0.5 / 0.9 均被接受（`setSpeechRate` 返回 1）；`awaitSpeakCompletion(true)` 下 `speak()` 返回 1，并在朗读结束后完成 Future（模拟器约 1.3s，桌面约 1.0s，含引擎启动时间）。
- 未做听感验证（无图形/音频会话），也未测 Android；后续真机阶段补测音质与 Android 引擎差异。

## 2. 数据

| 平台 | 语言数 | 中文语言 | zh-CN 可用 | 语音数 | 语速 0.1/0.5/0.9 | speak 返回 | 耗时 |
|---|---:|---|---|---:|---|---:|---:|
| iOS 模拟器 | 49 | zh-CN, zh-TW | true | 68 | 1 / 1 / 1 | 1 | 1340ms |
| macOS 26.7.1 | 49 | zh-TW, zh-CN | true | 180 | 1 / 1 / 1 | 1 | 1024ms |

## 3. 复现

```bash
cd apps/reader_mobile
flutter test integration_test/p0_20_tts_test.dart -d 0229CA7B-9D61-4DBA-B7DC-562DD39F9719
flutter test integration_test/p0_20_tts_test.dart -d macos
```

## 4. 限制与后续

- 朗读测试使用短句，未验证长句切分、后台播放、音频焦点中断；这些在 P6-07～P6-09 落地与验收。
- `flutter_tts` 当前插件未支持 iOS 的 Swift Package Manager（构建时有提示）；不影响 CocoaPods 流程，需在 P6 前关注升级。
- Android 无 AVD/许可未接受，未测。
