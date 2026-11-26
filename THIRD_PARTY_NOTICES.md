# 第三方资源与来源说明

项目根目录的 Apache License 2.0 仅适用于有权按该协议发布的原创代码。第三方代码、字体和数据继续遵守其原始许可证；文件改名、注释整理和删除本地参考资料不改变来源或授权状态。

## 自有项目迁入代码

`packages/epub_toolkit/lib/` 中部分处理逻辑迁自项目作者自有的 [wangyyyqw/epub-toolkit](https://github.com/wangyyyqw/epub-toolkit)，快照为 `de0c056c2bbb376c0f42f84f9d8a9c3612739524`。迁入本仓库的自有原创代码采用根目录的 [Apache License 2.0](LICENSE)；其中使用的第三方代码与资源继续遵守各自许可证。

## 已随仓库保留的声明

| 内容 | 声明与许可证 |
| --- | --- |
| 内置宋体 | [Adobe 版权声明与 SIL Open Font License 1.1](apps/reader_mobile/assets/fonts/LICENSE.txt) |
| 仅供测试的思源黑体 | [Adobe 版权声明与 SIL Open Font License 1.1](test_fonts/OFL-SourceHanSans.txt) |
| 英文断词数据 | [原始归属与 BSD 风格许可证](packages/reader_core/third_party/hyph_en_US/LICENSE.txt) |
| OpenCC 字典 | [Apache License 2.0](packages/epub_toolkit/assets/opencc/LICENSE) |
| HarfBuzz FFI 绑定 | [MIT 许可证及本地修改说明](packages/epub_toolkit/third_party/harfbuzz_ffi/LICENSE) |
| HarfBuzz 源码 | [原始版权与 Old MIT 许可证](packages/epub_toolkit/third_party/harfbuzz_ffi/third_party/harfbuzz/COPYING) |

桌面构建时加入的 WebP 工具及动态库，由 `packages/epub_toolkit/tool/bundle_cwebp_macos.sh` 复制对应许可证。Dart 与 Flutter 依赖按锁定版本及各自的上游许可证使用。

## ReaMicro 分支图标

ReaMicro 分支的应用图标使用用户指定的本地 `reamicro` 项目墨白素材（`ic_launcher_02`）；Android 直接复用原尺寸与单色层，其他平台仅适配图标尺寸。素材来源和权利仍归原项目。

## 网盘导入组件

网页登录使用 [flutter_inappwebview 6.1.5](https://pub.dev/packages/flutter_inappwebview/versions/6.1.5)（Apache-2.0）。Android 实现 1.1.3 的源码与 [原始许可证](third_party/flutter_inappwebview_android/LICENSE) 保存在 `third_party/flutter_inappwebview_android/`；为适配 AGP 9.1.0，仅将 Android 构建脚本中的默认 ProGuard 配置改为 `proguard-android-optimize.txt`。运行时逻辑未改。

标准密码算法使用 [pointycastle 4.0.0](https://pub.dev/packages/pointycastle/versions/4.0.0)（MIT），网页解析使用 [html 0.15.7](https://pub.dev/packages/html/versions/0.15.7)（MIT）。对应许可随依赖保留，并由 Flutter 许可清单收集。

七个网盘连接器根据官方网页接口与协议字段独立实现。未纳入 wenxi 的 AGPL 源码或 Gopeed 下载内核；网盘名称归各服务提供方所有，不表示官方合作或授权。协议核对来源包括 [阿里官方网页](https://www.alipan.com/drive)、[123 官方网页](https://yun.123pan.cn/)、[PikPak 官方网页](https://mypikpak.com/drive/all)，网页及接口可能随服务更新而变化。

## 内置思源宋体

正文与应用界面只内置基于 Adobe [Source Han Serif 2.003R](https://github.com/adobe-fonts/source-han-serif/releases/tag/2.003R) 制作的中文精简版，固定上游快照为 `7889f11bf31170b5d092a083b357c8c8130f89e0`。派生字体的内部名称和文件名改为 `Moyu Serif` / `MoyuSerif`，保留 Adobe 原始版权及 OFL 声明。

| 资源 | 官方原始文件 | SHA-256 |
| --- | --- | --- |
| 常规，字重 400 | [SourceHanSerifSC-Regular.otf](https://raw.githubusercontent.com/adobe-fonts/source-han-serif/7889f11bf31170b5d092a083b357c8c8130f89e0/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf) | `78aa7a328fd974df2d688c8a9fd74a33d8334dfa84ab24d9d11efb2ffc464117` |
| 粗体，字重 700 | [SourceHanSerifSC-Bold.otf](https://raw.githubusercontent.com/adobe-fonts/source-han-serif/7889f11bf31170b5d092a083b357c8c8130f89e0/OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf) | `706b8c0de2deff6cbc0c87e2cdedfd33a78b7ffd76cebb4549012f197ba611fe` |

精简后每个字重保留 **33,104 个字符、30,256 个汉字码点、42,647 个字形**。原字库全部汉字码点（含扩展区、兼容汉字）均保留，简体／繁体／港台地区字形、标点、拉丁字母、数字、常用符号、注音和假名仍可用。保留原字库的 25 组汉字异体字序列；删除韩文字符及日韩地区替换字形，保留字距、标点挤压、竖排等 OpenType 特性和字形提示；未覆盖字符继续由书内或系统字体回退。

| 打包资源 | 字重 | SHA-256 |
| --- | --- | --- |
| `MoyuSerif-Regular.otf` | 400 | `31769352272eb94d5544821db34c933850eb37f534fe708c1912ff2335bf5ec8` |
| `MoyuSerif-Bold.otf` | 700 | `2adc7ec027629f051da5e4d66da40f580437c9cb0c24a3b1e670701fe592c51d` |

生成脚本为 [tool/subset_bundled_fonts.py](tool/subset_bundled_fonts.py)，使用 `fonttools==4.68.0`。将上表两份官方原始文件下载到本地目录后，执行：

```bash
python3 tool/subset_bundled_fonts.py \
  --source-dir /path/to/source-han-serif-2.003 \
  --output-dir apps/reader_mobile/assets/fonts
```

脚本验证上游 SHA-256、保留码点清单、每个保留字符的字形边界及横竖度量。字体与派生文件均遵守 [OFL 1.1](apps/reader_mobile/assets/fonts/LICENSE.txt)，许可随源码和应用资源分发。`test_fonts/` 和 `assets/test_fonts/` 中的测试字库不作为正式 APK 资产打包。

## 听书组件与音色

系统朗读通过 [flutter_tts](https://pub.dev/packages/flutter_tts) 调用设备引擎；离线合成使用 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)，音频播放使用 [audioplayers](https://pub.dev/packages/audioplayers)。依赖版本固定在应用的 `pubspec.lock`，各组件遵守上游许可证。

超文、小雅音色原包取自 [sherpa-onnx 音色发布页](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)，应用从项目上传的 Streamshare 链接按需下载并校验 SHA-256，模型不随仓库或 APK 内置。下载包中的模型卡及许可文件原样保留，项目的 Apache 2.0 许可不覆盖这些模型。

| 音色 | 下载地址 | 原包 SHA-256 |
| --- | --- | --- |
| 超文 | [Streamshare](https://streamshare.wireway.ch/download/9wqtzm51) | `1b69bdcf10bb6331c7f8a7591940febeb175c6bb86caa3802d96531f8e4ad211` |
| 小雅 | [Streamshare](https://streamshare.wireway.ch/download/fyhe1qeg) | `9396a3dffbb95b037acaa18094500f58d0db9a7c4f2689554e2539717cf0db65` |

超文模型卡声明数据集为 CC0，并注明从小雅音色微调；小雅模型卡声明数据集限非商业用途。使用或再分发模型时应核对完整上游条款，不能把整个模型视为项目自有的 Apache 2.0 资源。

## EPUB 兼容标记

源码与合成测试中的厂商 CSS 前缀、OPF 属性、脚注类名及数据属性属于输入文件格式。为继续读取已有 EPUB，这些协议字符串和对应转换功能按原样保留。它们不表示与相关产品存在隶属、合作或背书关系。

私人书籍、原书摘录、截图、数据库、日志及历史验收附件不作为开源素材，留在 Git 忽略的本地目录中。

## ReaMicro 矢量界面图标

界面矢量路径来自 [YGHFv/ReaMicro-Extend](https://github.com/YGHFv/ReaMicro-Extend/tree/bed8e48896e2586c7da2064e180e250909af84d7)：宿主内嵌图标及布局图标。Miuix Regular 操作图标来自该版本内置的 compose-miuix-ui 子集，版权归 compose-miuix-ui contributors，采用 Apache-2.0。路径保存在 `packages/reader_ui/lib/icons/rea_micro_glyph.dart`，同步入口为 `tool/sync_reamicro_icons.py`。发现图标和未在参考项目中找到对应路径的应用字形保留本项目原实现。
