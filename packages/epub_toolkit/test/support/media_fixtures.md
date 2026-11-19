三份字体来自迁移参考工程自带的原创几何回归夹具，均约 1 KB，不包含用户书籍或商业字体。

- `media_subset_probe.ttf`：包含复合字形及补充平面码点，用于 cmap、轮廓和校验和检查。
- `media_complex_probe.ttf`、`media_complex_probe.otf`：包含连字、竖排和可选 GSUB 特性；OTF 使用真实 CFF 轮廓。

测试运行时生成 EPUB 和图像，临时文件随测试清理；不依赖网络或已安装的用户字体。
