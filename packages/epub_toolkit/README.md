# 编辑器本地 EPUB 工具

处理逻辑迁自 [wangyyyqw/epub-toolkit](https://github.com/wangyyyqw/epub-toolkit)，参考提交 `de0c056c2bbb376c0f42f84f9d8a9c3612739524`。只保留本地文件处理，不引入原项目的界面框架、书库、账号、网络下载、传书与邮件发送。

由宿主先导出当前编辑快照，后台处理独立的临时文件，核验结果后以一个编辑事务应用资源差异。原 EPUB 不直接覆盖；分册结果单独导出。撤销、重做、草稿、保存和手机分页仍由原编辑框架处理。按用户范围要求，不包含 TXT 导入、转换或导出。

## 功能范围

- 转换：EPUB 2／3 双向转换、OpenCC 简繁转换。
- 结构：本地体检与选择性修复、目录／地标／页码导航、结构重排、合并与按章节分册、资源名称混淆与还原。
- 图片：压缩、WebP 双向转换、隐形水印写入与读取；保留动图，避免覆盖同名目标资源。
- 字体：字体目标扫描、HarfBuzz 子集化、按字体族与章节选择原工具的字体加密。
- 注释与正文：正则清理、批注提取、脚注与弹窗互转、阅微／得到／掌阅注释转换、全文或生僻字拼音标注。

字体加密会改变正文码点，不等同于标准版权保护，会影响复制、搜索与朗读，界面需确认后执行。跨 XHTML 脚注不转换；拼音多音字使用词库首读音，未收录汉字原样保留。名称混淆不是内容加密。

## 依赖与资源

- 原项目的 `archive 3`、`xml 6`、`image 3` 不兼容阅读引擎当前依赖，改用现有 `archive 4`、`xml 7` 与 `image 4.13.1`，不以依赖覆盖强行锁定旧版本。
- OpenCC 四份压缩字典与许可证来自参考项目的 `assets/opencc/`，词组采用最长匹配；不能将该快照声明为某个特定 OpenCC 发布版本。
- 拼音使用 `pinyin 3.3.0`，不调用网络接口或运行时下载词库。
- HarfBuzz 源码、绑定、原许可证及本地修改说明保留在 `third_party/harfbuzz_ffi/`。编译使用原生资产 hook，不依赖运行时 Python 或系统 HarfBuzz。
- WebP 编码使用桌面 `cwebp`；macOS 构建后运行 `tool/bundle_cwebp_macos.sh`，复制本地组件、依赖动态库和许可证，重签名时保留应用原有权限。脚本可重复执行。开发环境可使用 `PATH` 中的组件，缺失时明确报错，不将未转换当成成功。

本次 macOS 实测为 Apple Silicon，复制的 WebP 组件仅含 `arm64`。脚本不进行交叉编译；Intel Mac 需要匹配架构的组件及动态库，不能据应用主程序的通用二进制格式推断 WebP 已支持 Intel。

## 验证

在本包运行以下回归；首次解析依赖优先使用 `flutter pub get --offline`，仅缺少缓存时联网补齐。

```bash
flutter test --no-pub test/chinese_converter_test.dart \
  test/local_dispatch_test.dart test/structure_tools_test.dart \
  test/media_tools_test.dart test/phonetic_test.dart
flutter analyze --no-pub
```

测试仅验证实际覆盖的本地处理和编辑链路，不代表 EPUBCheck 完整规范认证或第三方阅读器验收。
