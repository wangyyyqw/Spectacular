# 内置字体引擎

源码（HarfBuzz 14.2.1）和生成绑定来自 pub.dev 的 `harfbuzz_ffi 0.4.2`。
上游归档的 SHA256：
`c54642245610297770d8972dafbc3e330d46772be2860f15977793b6aeb5b937`.
原包的 `LICENSE` 和 HarfBuzz 的 `COPYING` 均保留。

本地集成修改：
- 使用 `native_toolchain_c` 替代 `native_toolchain_ninja`，避免其归档依赖与宿主冲突。
- 通过公共库导出生成绑定。
- 保留线程安全，支持 Flutter 后台 isolate。
- 子集化时保留空的 `vert`／`vrt2` 排版特性标记，避免 CFF 字体的竖排回退发生变化；几何字体回归保留相关排版表。
- 将 HarfBuzz 的 `COPYING` 纳入包级 `LICENSE`，供应用展示许可声明。
- 构建和运行均不下载源码，也不使用系统字体引擎。
- 导入源码仅统一文本换行和尾随空白。

原生资产 hook 使用 Flutter 的本地编译工具链，为目标系统和架构编译并打包 C++ 源码。本地实际验收为 macOS；其他平台需要各自构建验证。

## Spectacular 集成

构建依赖使用宿主已缓存的 `native_toolchain_c 0.19.5` 和 `code_assets 2.1`，避免为字体组件降级宿主 SQLite 与 Objective-C 的原生资产依赖。HarfBuzz 源码、生成绑定与资产标识保持不变。
