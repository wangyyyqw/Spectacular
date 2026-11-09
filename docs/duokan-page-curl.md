# 多看仿真翻页资料报告

> 目的：核实多看阅读 7.44.21 的仿真翻页契约，记录本项目 3D 翻页的移植与对照证据。
>
> 对象：`参考/duokan/多看_7.44.21.apk`（包名 `com.duokan.reader`，versionCode 744210000）
>
> 方法：JADX 与 DEX 指令核实、本地 Java 数值参照、原 `CurlMesh`/GLSL 的真机 GLES 离屏执行、Flutter 像素探针，以及两款应用的真机阅读与录像。
>
> 几何与着色公式的一致不等于整个应用逐像素 1：1；已执行结果与保留限制见第 15 节。

## 目录

1. [结论摘要](#1-结论摘要)
2. [模式与视图位置](#2-模式与视图位置)
3. [数据契约](#3-数据契约)
4. [坐标系](#4-坐标系)
5. [手势与状态机](#5-手势与状态机)
6. [CurlMesh 几何](#6-curlmesh-几何)
7. [着色与合成](#7-着色与合成)
8. [阴影模型](#8-阴影模型)
9. [动效参数汇总](#9-动效参数汇总)
10. [单页、双页与 RTL](#10-单页双页与-rtl)
11. [与排版引擎的边界](#11-与排版引擎的边界)
12. [未闭合项](#12-未闭合项)
13. [对新增仿真翻页类型的启示](#13-对新增仿真翻页类型的启示)
14. [关键证据索引](#14-关键证据索引)
15. [当前验证边界](#15-当前验证边界)

## 0. 阅读约定

全文使用以下证据标记：

```text
[静态确认]   源码或 DEX 指令、类关系、常量、调用链可直接读出；坏反编译分支以 DEX 为准。
[数值验证]   原 Java 几何逻辑已在本地执行并与 Dart 比较，不包含 Android 绘制或 GPU 执行。
[真机验证]   指定手机上实际执行了应用、Canvas 或 GPU 路径，结论仅覆盖执行条件。
[像素对照]   同尺寸、同素材和固定姿态的图像比较，不代表两款完整阅读页或所有设备一致。
[强结构推断] 由位置计算、着色器公式和对象用途共同支持，但没有逐帧对照。
[未验证]     尚未执行对应运行路径或逐帧、像素比对，不能据此宣称运行效果等价。
```

涉及文件缩写：

```text
CPV = 参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlPageView.java
CM  = 参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlMesh.java
CR  = 参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlRenderer.java
CP  = 参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlPage.java
CS  = 参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlStatic.java
PP  = 参考/duokan/reverse/jadx/sources/fi/harism/curl/PageProvider.java
W   = 参考/duokan/reverse/jadx/sources/com/duokan/reader/ui/reading/w.java
RV  = 参考/duokan/reverse/jadx/sources/com/duokan/reader/ui/reading/ReadingView.java
FPV = 参考/duokan/reverse/jadx/sources/com/duokan/reader/ui/general/FlowPagesView.java
PIPE = 参考/duokan/reverse/native/libdkkernel_epub_pipeline.md
TG  = /Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/ui/i.java
FG  = /Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/ui/b.java
GC  = /Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/ui/j.java
MK  = /Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/widget/mk3.java
BM  = /Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/utils/a.java
```

## 1. 结论摘要

1. 仿真翻页是**独立动画层**，不进入 native 排版。[静态确认]
2. 实现是 `GLSurfaceView` + OpenGL ES 2.0，三组 `CurlMesh`（左静态页、卷曲页、右静态页/背景），每组三张纹理。[静态确认]
3. 卷曲页的几何是**页面矩形 → 旋转 → 扫描线求交 → 半圆柱映射 → 背面折返**；角点 UV 固定，扫描交点的 UV 沿原纸边插值。每帧顶点数量可以变化，图案仍附着在同一纸面坐标上。[静态确认 + 数值验证]
4. 页面内容来自 `DocPageView.draw(Canvas)` 生成的 **RGB_565** 位图；双页模式按左右半页裁剪。[静态确认]
5. 正反面由片元内归一化后的插值法线 `normal.z > 0.1` 决定。单页前进卷当前页，后退卷上一页；其背面均为 **5% 被卷纸页 + 95% 背景**。双页的背面槽可能绑定同一张邻页，不能统一解释为背景。[静态确认]
6. 阴影是独立连续三角形带：drop shadow 取 `0 < z <= r`，self shadow 取 `z > r`；每个基点配一个 alpha 为 0 的半影端点，片元 alpha 再乘 0.5。[静态确认 + 数值验证]
7. 起手在页面上/下三分之一内会吸附到边缘，否则进入中心模式；中心模式强制 `y = pageCenterY`，形成竖直折痕。[静态确认]
8. 最大卷曲半径 `R = pageRect.width() / 6`。`updateCurlPos` 计算的是折痕中心位移 `shift`，传入 `setCurlPos` 的半径仍为 `R`；只有折痕中心越过远侧页边时才减小半径，且下限为 0。[静态确认 + 数值验证]
9. 起手动画上限 100ms，松手有 `max(|dx| * 150, 150) ms` 的 smoothstep 收尾，`dx` 是 GL 坐标差；页码提交发生在收尾动画结束后。[静态确认]
10. 20dp 配置给甩动检测器的最低速度，不是起拖距离；起拖使用系统 touch slop、方向和采样门槛。`setCurlPos` 自行请求下一帧，实际手势触发距离和帧率仍需运行对照。[静态确认 / 未验证]

## 2. 模式与视图位置

### 2.1 六种阅读动画

```java
PageAnimationMode.java
NONE("无")
HSCROLL("平移")
VSCROLL("上下")
OVERLAP("覆盖")
FADE_IN("淡入")
THREE_DIMEN("仿真")
```

[静态确认]

默认是 `OVERLAP`（`ReadingPrefs.java:564-570`）。`THREE_DIMEN` 是设置里的“仿真”，也是本文对象。

### 2.2 两层视图

`ReadingView.p()` 把阅读模式同时映射到两层：

| 阅读模式 | 底层 `FlowPagesView.FlipEffect` | 页面布局 | 仿真层 |
|---|---|---|---|
| `NONE` | `NONE` | 按书写方向左右 | 隐藏 |
| `HSCROLL` | `SCROLL` | 按书写方向左右 | 隐藏 |
| `VSCROLL` | `OVERLAP` | `TOP_TO_BOTTOM` | 隐藏 |
| `OVERLAP` | `OVERLAP` | 按书写方向左右 | 隐藏 |
| `FADE_IN` | `FADE_IN` | 按书写方向左右 | 隐藏 |
| `THREE_DIMEN` | 回退 `SCROLL` | 按书写方向左右 | `CurlPageView` 覆盖 |

[静态确认] `RV:726-775`

底层 `FlowPagesView.FlipEffect` 只有四个值：`NONE`、`SCROLL`、`OVERLAP`、`FADE_IN`。[静态确认] `FPV:47-51`

关键点：进入仿真模式后，普通流式视图并没有消失，而是被设为 `SCROLL`，由全屏 `CurlPageView` 盖住。这样翻页失败、取消或动画结束时，底层页面仍然在正确位置。

### 2.3 切换时序

`W.k6(PageAnimationMode)`：

```text
进入 THREE_DIMEN:
  flowPages.H0(false)
  wf()                       // 取背景图
  curlView.setVisibility(VISIBLE)

离开 THREE_DIMEN:
  flowPages.H0(true)
  curlPageCache.e()          // 清理页面位图缓存
  curlView.setVisibility(INVISIBLE)
```

[静态确认] `W:687-701`

`CurlPageView` 是懒加载的，加入时索引为 0：

```text
RV:642-649
new CurlPageView(context)
c.addView(curlView, 0, MATCH_PARENT, MATCH_PARENT)
```

索引 0 表示它在页面容器的最底层，阅读菜单等后加入的视图仍在其上。

## 3. 数据契约

### 3.1 PageProvider

仿真层只认这些接口，不认 HTML、行盒或 native 页面对象：

```java
Bitmap getPageBitmap(CurlAnchor anchor);
Bitmap getBackgroundBitmap();
CurlAnchor nextPageAnchor(CurlAnchor anchor);
CurlAnchor prevPageAnchor(CurlAnchor anchor);
boolean isFirstPage(CurlAnchor anchor);
boolean isLastPage(CurlAnchor anchor);
void flipPage(CurlDirection direction);
void afterFlip(boolean cancelled);
void afterDrawFrame();
void afterSurfaceChanged();
void onPageSizeChanged(int width, int height);
```

[静态确认] `PP:1-28`

多看的实现是 `W` 内部类：

```text
getCurrentPageAnchor  <- uf() 从 p.Q0() 取当前页 drawable；双页取 r30.n()
getPageBitmap(anchor) <- w.g.n(anchor.mPageDrawable)
getBackgroundBitmap() <- w.g.i().f6282a
next/prevAnchor       <- p.t1(+1) / p.t1(-1)，双页分别取 n()/i()
flipPage(direction)   <- kk1 异步投递 p.q() / p.k1()
afterFlip             <- kk1 异步刷新阅读状态
```

[静态确认] `W:235-288`

`CurlAnchor` 只包一个 drawable 引用：

```java
public class CurlAnchor {
    public w02 mPageDrawable = null;
    public boolean isValid() { return mPageDrawable != null; }
}
```

[静态确认] `CurlAnchor.java:1-12`

### 3.2 页面位图捕获

`W` 的页面缓存 `g` 生成位图：

```text
遍历 flowPages.getPageViews()
  -> DocPageView.getPageDrawable()
  -> 只接受 W0() 为真的页面
  -> 单页：分配 DocPageView 宽高的 RGB_565 Bitmap
            docPageView.draw(new Canvas(bitmap))
  -> 双页：分配半宽 RGB_565 Bitmap
            根据左/右半页和阅读方向决定是否 canvas.translate(-半宽, 0)
```

[静态确认] `W:1012-1057`；分配函数 `BM:387-388 → BM:110-112` 将 `Bitmap.Config.RGB_565` 原样传给 `Bitmap.createBitmap`。

三个直接后果：

- 位图是**页面最终外观**，包含正文、图片、装饰；
- 位图尺寸与当前排版一致，动画层不做缩放决策；
- RGB_565 每像素 2 字节，红/绿/蓝分别为 5/6/5 位，不保存 alpha；精度降低可能形成色带或偏色。

这里是**直接在 RGB565 Bitmap 上绘制页面**，没有先捕获 RGBA 再调用自定义颜色量化函数。页面的颜色、抗锯齿和透明图层先由 Android Canvas 合成到这张位图，之后才交给 GL。

背景走另一条路径：`W:824` 从 `o.q0.a()` 取图，`W:827-829` 调 `BM.b(bitmap)`，`BM:379-380 → BM:148-150` 使用 `Bitmap.createBitmap(source)` 保留源格式。源图由 `o.Lh()` 生成：普通主题使用 RGB565；仅 `THEME14 && !k80.W() && SDK != 31` 使用 ARGB8888。[静态确认] `o.java:4996-5010`。因此普通主题的纸底也经过 565 量化，特殊主题不能统一解释为 RGB565。

[静态确认] 格式定义见 [Android Bitmap.Config.RGB_565 官方文档](https://developer.android.com/reference/android/graphics/Bitmap.Config#RGB_565)。本轮纯色色块的完整通道实测见第 15 节；直接 Canvas RGB565 的抗锯齿/透明合成与先绘制 RGBA 再量化仍有不同验证边界。量化应作用于页面与纸底的采样值，随后才进行背面混色和阴影，不能统一量化最终着色结果。

### 3.3 缓存与生命周期

缓存结构：

```text
Map<w02, h>       按页面 drawable 索引
Queue<h>          可复用缓存项
h.f6282a          Bitmap
h.f6283b          本轮是否被 PageProvider 引用
```

[静态确认] `PIPE:6428-6455`

流程：

```text
A(offset)：处理当前页 ±1 候选；扫描并回收本轮未引用项；复用 Queue 中的 h
n(drawable)：命中则标记引用并返回；未命中返回背景缓存项
i()：取背景缓存项并标记引用
b()：清空引用标记，供下一轮预取重算
e()：释放页面和背景位图，清空预取队列
```

[静态确认]

重要时序：`n()` 返回的 Bitmap 必须在 GL 上传纹理期间保持有效；`getTextures()` 完成 `GLUtils.texImage2D` 后才调用 `mPage.recycle()` 释放引用。复刻时要把“位图缓存”和“纹理上传”分开管理。

### 3.4 CurlPage 的三个纹理槽

```java
SIDE_FRONT = 1
SIDE_BACK  = 2
SIDE_BACK2 = 3
SIDE_ALL   = 4   // 三个槽写同一张图
```

[静态确认] `CP:1-87`

`onDragStart` 的单页绑定已从 DEX 的 `:cond_be/:cond_d7/:cond_f4` 到公共 `:goto_1a8` 复核。设 A 为当前页、P 为上一页、N 为下一页，且所需邻页存在：

| 单页组合 | 被卷纸页，front 槽 | 可见底页 | back 槽 | back2 槽 |
|---|---|---|---|---|
| LTR，PAGE_DOWN 前进 | A | N（右静态 mesh） | A | 背景 |
| LTR，PAGE_UP 后退 | P | A（右静态 mesh） | P | 背景 |
| RTL，PAGE_DOWN 前进 | A | N（左静态 mesh） | A | 背景 |
| RTL，PAGE_UP 后退 | P | A（左静态 mesh） | P | 背景 |

[静态确认] 单页页身份对应 `CPV:355-370、490-498`；实际槽位写入以 `classes7.dex` 中 `onDragStart` 的公共绑定段为准：`p2` 是左静态页、`v4` 是右静态页、`v6` 是卷曲 front、`v5` 是可选背面邻页。右静态页在锚点无效时绑定背景，左静态页和卷曲页在锚点无效时跳过。

所以后退动画应准备并变形 **P 的纸面**，当前页 A 是它下面的静态页。不能在两个方向都卷 A，也不能把单页纸背的 5% 图案统一指向底页 N/A。

双页路径若背面邻页存在，会将同一邻页位图同时写入槽 2、3；不存在时才退回 `back = front、back2 = 背景`。这意味着 `0.05 * back + 0.95 * back2` 在两槽相同时就是完整邻页图。JADX 的 `anchor == null && anchor.isValid()`、重复绑定块和空分支不能照抄；DEX 实际使用非空且有效的判断。双页边界及其运行观感尚未验证。

### 3.5 一次翻页的完整时序

```text
触摸
  -> W.j 的 TranslateGesture 经系统 slop、方向和采样门槛接管
  -> CurlPageView.onDragStart
       -> 取当前页与前后邻页锚点
       -> 取页面位图 / 背景位图
       -> 三组 mesh 绑定纹理与页面矩形
       -> 起手动画，时长上限 100ms
  -> onDragMove 更新指针
  -> onDrawFrame -> updateCurlPos -> setCurlPos -> CurlMesh.curl
  -> 松手由甩动速度或 10dp 累计位移决定方向，再调用 onDragEnd
       -> 计算 target 与 duration
       -> smoothstep 收尾
       -> 动画结束 flipPage(direction)
       -> afterFlip(false)
       -> PageProvider 刷新阅读状态与页面缓存
```

[静态确认] 各步位置见第 5 节；帧循环由 `setCurlPos` 请求下一帧，见 5.3。

### 3.6 位图到纹理的交接

```text
PageProvider.getPageBitmap(anchor)
  -> CurlPage.setBitmap(bitmap, slot)
  -> CurlMesh.getTextures()
       -> 首次：glGenTextures(3)
       -> 位图变化：GLUtils.texImage2D × 3
       -> 上传完成：mPage.recycle() 清空 Bitmap 引用
```

[静态确认] `CM:476-498`、`CP:52-56`。三张纹理均直接传给 `GLUtils.texImage2D`，本应用代码没有额外的 RGB565 转换或片元量化；Android GLUtils 内部与 GPU 的实际上传格式、展开和精度不在 Java 数值 oracle 的覆盖范围内。

这意味着 `CurlPage` 在运行时主要承担“位图 → 纹理”的搬运，不长期持有像素。复刻时如果保留 Bitmap 供后续帧使用，内存模型会与多看不同。

## 4. 坐标系

### 4.1 GL 视口与正交投影

`CurlRenderer.onSurfaceChanged`：

```text
glViewport(0, 0, width, height)
viewRect.top = 1, bottom = -1
viewRect.left = -aspect, right = aspect      // aspect = width / height
orthoM(-aspect, aspect, -1, 1, -10, 10)
glDisable(GL_DEPTH_TEST)
glDisable(GL_CULL_FACE)
```

[静态确认] `CR:188-215`

这里的关键是：**z 只用于着色和阴影判断，不参与深度测试**。绘制顺序完全由 mesh 的加入顺序决定。

屏幕坐标转换：

```text
translate(p):
  p.x = viewRect.left + viewRect.width  * p.x / viewportWidth
  p.y = viewRect.top  - (-viewRect.height) * p.y / viewportHeight
```

[静态确认] `CR:252-257`

即 `x` 映射到 `[-aspect, aspect]`，`y` 从 `1` 向下映射到 `-1`。

### 4.2 三种页面矩形

`updatePageRects()`：

| viewMode | 含义 | 左页矩形 | 右页矩形 |
|---|---|---|---|
| 0 | 单页显示左页 | 视口减去 margins | 左页右移一页宽 |
| 1 | 单页显示右页 | 右页左移一页宽 | 视口减去 margins |
| 2 | 双页 | 视口左半 | 视口右半 |

[静态确认] `CR:56-100`

页面尺寸回调：

```text
pagePixelWidth  = pageRect.width  * viewportWidth  / viewRect.width
pagePixelHeight = pageRect.height * viewportHeight / viewRect.height
```

[静态确认] `CR:69`

这也是 `PageProvider.onPageSizeChanged` 的来源。

### 4.3 margins

`setMargins(left, top, right, bottom)` 直接修改页面矩形，单位为视口比例。[静态确认] `CR:236-241`

阅读器当前是否传入非零 margins 未在本次范围内确认。[未验证]

## 5. 手势与状态机

### 5.1 CurlPageView 状态字段

```text
mAnchor              当前页锚点
mCurlDirection       PAGE_UP / PAGE_DOWN
mDragStartDir        -1 / 0 / 1
mDragEndDir          -1 / 0 / 1
mDragStartPos        拖动起点（GL 坐标）
mMovingPos           当前卷曲驱动点
mPointerPos          当前指针（GL 坐标）
mCenterMode          是否中心起卷
mAnimating           是否处于收尾/起手动画
mAnimationSource/Target/StartTime/DurationTime
mCurlMaxRadius       pageRect.width() / 6
mViewMode            SHOW_ONE_PAGE / SHOW_TOW_PAGE
mRtlMode             是否 RTL
mQuality             网格质量
mMeshLeft/Curl/Right 三组网格
```

[静态确认] `CPV:16-43`

### 5.2 起手

`onDragStart(point, direction)` 的步骤：

```text
1. 若正在动画，直接返回
2. 记录 pointer、direction、起点
3. 按单页/双页设置 renderer view mode
4. 双页时 meshCurl.backReverse = 1
5. 取左右页矩形
6. mCurlMaxRadius = pageRect.width() / 6
7. 移除旧 mesh
8. 按方向和 RTL 取当前页、上一页、下一页锚点
9. 左/右静态页绑整页纹理
10. 卷曲页绑 front / back / back2
11. 起点 y 吸附到上边缘、下边缘或页面中心
12. 启动起手动画，时长 max 100ms
```

[静态确认] `CPV:300-545`

吸附条件：

```text
|startY - page.top|    < page.height / 3  -> top
|startY - page.bottom| < page.height / 3  -> bottom
否则                                      -> center
```

[静态确认] `CPV:529-538`

中心模式不是“不吸附”，而是把起点强制到 `page.centerY()`，所以中心起卷一定是竖直折痕。

JADX 对这段复杂分支有重复块，并出现 `curlAnchor2 == null && curlAnchor2.isValid()` 这种明显不可达写法；可确认“会准备三组 mesh”，不能把每一行当作原始控制流。[未验证] `PIPE:6480-6488`

### 5.3 拖动

`onDragMove` 只做：

```text
pointer = translate(point)
mPointerPos = pointer
```

此方法不调用 `requestRender()`。[静态确认] `CPV:288-296`

`onDrawFrame` 在非动画状态下调用 `updateCurlPos(mPointerPos)`。[静态确认] `CPV:545-560`

帧驱动链是 `onDrawFrame → updateCurlPos → setCurlPos → requestRender`。`setCurlPos` 的页边提前返回分支也先请求重绘，因此存在手势时会持续申请下一帧，并不依赖 `onDragMove` 再请求一次。`mDragStartDir == 0` 时 `onDrawFrame` 直接返回，结束这条循环。[静态确认] `CPV:104-107、138-140、180、234、550-557`。实际 vsync 节奏、GPU 完成时间和掉帧尚未验证。

### 5.4 折痕中心位移与常数半径

```text
R = mCurlMaxRadius = pageRect.width() / 6
arc = πR
v = pointer - anchor
distance = |v|

distance >= arc:  shift = -(distance - arc) / 2
distance > 0:     shift = sqrt(arc * distance) - distance
distance == 0:    shift = 0

C = pointer + v * shift / (distance > 0 ? distance : 1)
setCurlPos(C, v, R)
```

[静态确认] `CPV:195-196、219-234`；`classes7.dex` 的 `updateCurlPos` 最后向 `setCurlPos` 传入保存 `mCurlMaxRadius` 的寄存器对，计算的 `d` 只用于修改 `pointF8`。旧稿把 `d` 当成半径，结论错误。

`shift` 在 `distance = arc/4` 附近达到最大值 `arc/4`，到 `arc` 时归零，之后为负；这些都只改变 C 的位置。半径不随该分段公式归零或转负。

单页后退会先把虚拟起手点投影到可见页边。规范 LTR、页面宽 W 时，后退的 `grab.x = -W`，有效 anchor 为：

```text
anchor.x = W
anchor.y = pointer.y + (W - pointer.x) * (pointer.y - grab.y)
                             / (pointer.x - grab.x)
```

分母为 0 时保持起手 y。单页 RTL 使用镜像页边。[静态确认] `CPV:199-217`。这一步解释了后退起手为何不是直接以屏幕左侧触点作为折痕锚点。

### 5.5 越界钳制

`setCurlPos` 处理的是折痕中心 C，实际触点不会被拉回页面。右页分支在 `C.x < page.left` 时、左页分支在 `C.x > page.right` 时收缩半径：

```text
radius' = max(R - (C 的越界距离 * 1.05 * 2) / π, 0)
C.x 钳制到对应页边
```

同时修正方向向量，避免折痕与页边的交点越出页面上下边界。[静态确认] `CPV:98-179`；DEX 明确使用 `page.right - C.x` 或 `C.x - page.left`，JADX 的未定义 `r14` 不能照抄。

换算为页面 `[0,W] × [0,H]`、y 向下的规范 LTR 坐标后，方向约束为：

```text
hitY = C.y + C.x * v.x / v.y       // v.y != 0
v.y > 0 且 hitY > 0:  v = (-C.y, C.x)
v.y < 0 且 hitY < H:  v = (C.y - H, -C.x)
u = normalize(v)
e = (u.y, -u.x)                   // 保持原 GL 扫描顺序
```

### 5.5.1 页边提前返回与保留上一帧

左页分支 `C.x <= page.left`、右页分支 `C.x >= page.right` 时只执行 `requestRender(); return;`，没有调用 `curl()`、`reset()` 或清空阴影。因此保留当前网格及 drop/self shadow 缓冲；这不是“返回一张平面纸”。[静态确认] `CPV:104-107、138-140`；DEX 对应 `setCurlPos` 的 `:cond_3f`、`:cond_a3` 之前。

提前返回发生在零方向检查之前；回到起手页边时，即使位移为零也先保留上一帧。只有未命中页边返回、且约束后的方向长度为 0，才调用 `mMeshCurl.reset()`。[静态确认] `CPV:170-179`。新一轮 `onDragStart` 另行设置矩形、纹理并 reset 网格，不能把保留行为跨手势、跨页面或跨视口尺寸复用。

移植结论：应由持有上一帧的控制或绘制层区分“保留”与“复位”。无状态几何对象返回 inactive 平面只是一种 API 表达，直接用它覆盖上一帧会改变原生退回起手边缘的行为。

### 5.6 松手

`onDragEnd(point, releaseDirection)`：

```text
mDragEndDir = releaseDirection.x > 0 ? 1 : -1
mAnimationSource = 当前显示位置（或指针）
mAnimationTarget = mDragStartPos
若 mDragEndDir * mDragStartDir > 0:
    target.x = getPageRect(2).left * 2 - target.x   // 翻到另一侧
duration = max(round(|source.x - target.x| * 150), 150)
```

[静态确认] `CPV:267-290`

上式的水平差值在 GL 坐标中计算，不能直接把像素距离乘 150。无 margins 的全屏页面，像素 dx 换算为 GL dx 的比例为 `2 / viewportHeight`。[静态确认] `CR:252-257`。

收尾插值：

```text
t = elapsed / duration
ease = t * t * (3 - 2t)
position = source + (target - source) * ease
```

[静态确认] `CPV:578-587`

结束：

```text
若 mDragEndDir != 0:
    若 mDragEndDir * mDragStartDir > 0:
        PageProvider.flipPage(direction)
    清空方向
    flipFinish()
否则:
    requestRender()
```

[静态确认] `CPV:560-575`

`flipFinish()` 调 `afterFlip(false)`，再执行可选 `mOnFinish`。[静态确认] `CPV:86-96`

**页码提交在动画结束之后**，与当前项目的 `PageTurnController._finish()` 一致。

### 5.7 边缘自动翻页

```text
pageDownSmoothly:
  起点固定在页左边缘，y 取触点或页面中心
  onDragStart(PAGE_DOWN)
  Thread.sleep(50)
  onDragEnd(起点, (mDragStartDir, 0))

pageUpSmoothly:
  同样从页左边缘
  Thread.sleep(75)
  onDragEnd(起点, (mDragStartDir, 0))
```

[静态确认] `CPV:612-640`

两个 `Thread.sleep` 出现在触摸控制路径，是否位于主线程、是否造成掉帧需要动态确认。[未验证]

### 5.8 外层手势阈值

`W.j` 同时使用平移和甩动两个检测器，不能只按常量名推断单位：

```text
g = com.duokan.core.ui.i     // TranslateGesture
h = com.duokan.core.ui.b     // FlingGesture
p = 10                      // 松手累计位移阈值，dp 换算为 px
```

[静态确认] `W:369-379`。

`J(view, z)` 里设置：

```text
g.i0(mk3.h0(context))       // 系统 scaledTouchSlop，像素距离
g.h0(0)                    // 后续平移距离门槛
g.d0(2)                    // 采样计数门槛，不是距离
g.g0(-50), g.f0(50)         // 方向角范围，不是速度范围
h.d0(F(view, 20))          // 最低甩动速度；配置值先按 density 换算
```

[静态确认] `W:594-606`；`MK:1133-1134` 返回 `getScaledTouchSlop()`；`GC:43-44` 的 `F(view, n)` 返回 `round(density * n)`。

实际平移检测先比较位移平方与系统 slop 平方，并检查方向；随后计数超过 `l = 2` 才回调，且每次保存采样起点。[静态确认] `TG:55-77、125-129、143-164`。由此能确定它不是固定 20dp 起拖；实际触发距离还受设备 slop、MOVE 采样和合并影响，尚未真机测量。

`h.d0` 设置的是 FlingGesture 的最低速度字段 `i`，释放时 `computeCurrentVelocity(1000)` 得到 px/s，再与该阈值比较。[静态确认] `FG:43-48、95-97`。因此这里的 20 是经 dp 换算后的**速度阈值数值**，不能写成 20dp 拖动距离。

`H(view, event, ...)` 的规则：

```text
若仿真层不可接管：直接结束
尚未起拖时，指针数 > 1：停止本轮检测
尚未起拖时，若正在动画或存在未完成手势：拒绝新的拖动
已经起拖时：继续检测平移/甩动，不执行上述多指停止分支
释放时：
  threshold = F(view, 10)
  根据累计位移 j.x 与 threshold 的关系，决定 ReleaseDirection 的符号
  调用 onDragEnd(point, ±1 方向)
```

[静态确认] `W:524-586`。原平移检测器在已起拖后还支持间距与角度基本不变的双指平移（`TG:84-131`），不能把多指取消推广到整个手势生命周期。

在没有先被甩动检测器接管的释放分支，外层用累计位移与 10dp 换算值的严格比较决定方向符号，`CurlPageView` 再比较该符号与起手方向。甩动路径则直接用速度方向调用 `onDragEnd`。[静态确认] `W:398-405、548-584`。这属于位移/速度方向判定，不是页宽百分比；10dp 也不能当作所有释放方式的唯一完成条件。

## 6. CurlMesh 几何

### 6.1 固定纹理坐标

`CurlMesh.setRect(RectF)` 只设置四个顶点的 `mPosX/mPosY`；`setTexture()` 一次性设置：

```text
(0,0) (0,1) (1,0) (1,1)
```

[静态确认] `CM:534-556`

`curl()` 全程只修改 `mPosX/mPosY/mPosZ`、法线和阴影半影，**不修改 `mTexX/mTexY`**。扫描线求交时，交点纹理坐标按同一条边的比例插值：

```java
remove.mTexX += (vertex.mTexX - vertex2.mTexX) * d4;
remove.mTexY += (vertex.mTexY - vertex2.mTexY) * d4;
```

[静态确认] `CM:170-190`

这是“纸背内容不会游动”的根本原因：图案始终附着在纸面顶点上，看到的变形只来自顶点位置变化。

### 6.2 矩形与旋转

四个角顶点来自 `setRect`。`curl()` 先做：

```text
translate(-C.x, -C.y)           // C 是折痕中心，不是实际触点
angle = acos(direction.x)
direction.y > 0 时 angle = -angle  // 此处是 GL 的 y 向上坐标
rotateZ(-angle)
```

[静态确认] `CM:225-245`

旋转后按 **x 降序，同 x 时 y 降序**插入四个角点，用于确定扫描范围。原 `Vertex.rotateZ` 的矩阵是 `(x*cos+y*sin, -x*sin+y*cos)`，不要套用相反旋向的矩阵。[静态确认] `CM:63-77、233-245`；排序的 JADX 坏循环已按 DEX `:goto_54` 到 `:goto_7d` 复核，每个角点只插入一次。

### 6.3 扫描线

```text
d18 = π * radius
scanLines = [0]
for i = 1 .. splits-1:
    scanLines.add(-d18 * i / (splits - 1))
scanLines.add(minX - 1)
previous = maxX + 1
```

[静态确认] `CM:272-286`；DEX 的扫描分母明确是 `mMaxCurlSplits - 1`，不是 JADX 的未定义 `r15`。

`splits` 来自 `mMaxCurlSplits`。控件初始化为 15，阅读器 `vf()` 的 DEX 确定设置为 20（见 6.7）；该配置把圆柱半周分为 19 个等间隔，连同末尾折返边界共有 21 条扫描边界，纸面缓冲最多 46 顶点。

### 6.4 交点与顶点序列

对每个 `[scan, previous]` 扫描带：

```text
1. 四角按已排序顺序遍历，包含 x 落在闭区间的原角点。
2. 在角点的 x 上与矩形边严格求交：a.x > scan 且 b.x < scan。
3. 恰好一个交点时，把角点和交点按 y 降序加入；零交点只加角点；
   两交点时不加入该角点。
4. 当前 scan 恰有两个交点时按 y 降序加入；一个交点不加入。
5. 对输出顶点按扫描阶段变形，连续追加到同一个 triangle strip。
6. previous = scan，继续下一带，不把各带拼成独立二维网格。
```

[静态确认] `CM:288-364`；原边索引是 `(0,1)、(0,2)、(1,3)、(2,3)`，若排序后的 0→2 比 0→3 更长，第二、第三条改为 `(0,3)、(1,2)`。[数值验证] 中心和上下角的顶点数量及代表性 strip 样本已与 Java oracle 对照。

交点比例为 `(scan - b.x) / (a.x - b.x)`，局部 y 和固定 UV 都从 b 沿同一比例插值。JADX 的 `getIntersections` 在成功分支和循环尾部重复显示索引增长；DEX `:goto_83` 实际每条边只增长一次，照抄 Java 会漏边。不要额外去重边界角点或半径为零时的重复扫描线；原生允许退化三角形。

### 6.5 圆柱映射

除首条和末条扫描线外：

```text
θ = (x / πr) * π = x / r
x' = r * sin(θ)
z' = r - r * cos(θ)
n  = (sin(θ), 0, cos(θ))
```

[静态确认] `CM:330-360`

`x` 为旋转后的扫描坐标，范围约 `0 .. -πr`。因此：

| x | θ | x' | z' | 法线 z | 可见面 |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 正面 |
| -πr/2 | -π/2 | -r | r | 0 | 侧面 |
| -πr | -π | 0 | 2r | -1 | 背面 |

参数上覆盖 0 到 -π 的弧长；实际可见段由扫描线范围决定，不保证每次都走满 180°。可确认的是：中间扫描线按上式卷到圆柱面，末端单独折到背面。

本地 Java oracle 使用 400×600 页面、中心水平起手 `(400,300)`，得到以下页面像素坐标。半径收缩两行已包含 `setCurlPos` 的左边界钳制：

| 水平拖动距离 | 实际半径 | 折痕 C.x | 原右页角投影 x |
|---:|---:|---:|---:|
| 0 | 66.666667 | 400 | 400，起手平面 |
| 20 | 66.666667 | 335.279144 | 390.302155 |
| 120 | 66.666667 | 241.466904 | 287.568481 |
| 240 | 66.666667 | 175.280243 | 160 |
| 680 | 36.773714 | 0 | -284.471985 |
| 800 | 0 | 0 | -400 |

[数值验证] 初拖 20 时指针 x 为 380，而页角 x 约 390.302；原生起卷并不要求页角从第一帧起精确落到触点上。拖动跨过 `πR` 也不会使半径变负。此表是数学执行结果，不是 Android 屏幕测量。

### 6.6 背面折返

最后一个扫描带的剩余顶点单独折返；半径为 0 时，首带之后也走此分支：

```text
mPosX = -(mPosX + πr)
mPosZ = 2r
n = (0, 0, -1)
penumbraX = -penumbraX
```

[静态确认] `CM:338-350`

此映射把超过圆柱半周的纸面平铺到 `z = 2r`，并在卷曲局部 x 方向折返；不是额外镜像 UV。半径为 0 时 z 也为 0，仍可有背面法线 -1，但不会产生两类阴影。

`Vertex.mPenumbraX/Y` 的变换不直接传给纹理着色器；最终阴影由独立 `ShadowVertex` 按 z 和方向重新计算，不能用这里的顶点半影字段代替第 8 节公式。[静态确认] `CM:366-391`、`CR:145-157`、`CS:6、8`。

### 6.7 网格质量

构造：

```text
mMaxCurlSplits = max(1, quality)
顶点缓冲容量 = splits * 2 + 6
```

[静态确认] `CM:110-150`

阅读器计算：

```text
F = (screenRGB565Bytes * (twoPage ? 4 : 2) / 1024) / 1024  // 整数除法
maxMemory / totalMemory / freeMemory（MB）
quality = round(pow((F/max) * (free/total) * (1 - total/max), qx0.l) * 12 + 8)
```

[静态确认] `W:815-820`

`vf()` 的 DEX 明确把 0.0 传给 `Math.pow`，随后乘 12.0f、加 8.0f 并 round，结果为 20；这不是 JADX 丢失指数造成的推断。[静态确认] `classes4.dex` 的 `com.duokan.reader.ui.reading.w.vf()`。控件初始化的 15 与阅读器后续设置的 20 是不同阶段，不再列为常量疑点。

`setAnimationQuality` 一旦变化会销毁并重建三组 mesh，然后重新 `setTexture()`：

```text
destroyCurlMesh × 3
new CurlMesh × 3
setTexture × 3
```

[静态确认] `CPV:653-668`

### 6.8 静态页与卷曲页

- 未卷曲的左右页：`reset()` 只写入四个角顶点，纹理铺满整页。[静态确认] `CM:497-520`
- 卷曲页：`curl()` 生成扫描线顶点带。[静态确认]

### 6.9 Java oracle 的覆盖范围

本次数值参照保留原 `CurlMesh` 的 `Vertex` 运算、FloatBuffer 写入和阴影排序，只按 DEX 修复三处不可执行/错误的 JADX 输出：角点排序循环、求交循环重复增长、扫描分母 `r15`。`updateCurlPos/setCurlPos` 的位置与页边公式按同一 DEX 语义输入；Android 图形类型使用最小桩，不执行 Canvas 或 GL。

当前 [Dart 几何回归测试](/Users/aaa/Documents/demo/Spectacular/packages/reader_ui/test/paging/curl3d_geometry_test.dart:135) 的 11 项测试已通过：常数半径、20 像素起卷、平面、原生扫描、上下角、上下越界方向、左侧收缩、后退虚拟起点、阴影样本、固定 UV 与有限拓扑，以及屏幕片元反查。空间数值对 Java 浮点输出的容差为 0.001 页面像素，法线与 alpha 为 1e-6；反查覆盖 13 个姿态的非退化三角形，纸面坐标和完整法线与重心插值相差不超过 1e-7。

这些测试不能证明真机前后纹理内容、颜色量化、抗锯齿、片元分支边界、触摸事件节奏、动画时长或 Flutter 性能已经一致。

## 7. 着色与合成

### 7.1 纹理着色器

下列主体与 `CS:7` 等价。`vNormal` 来自顶点属性的线性插值；必须先在**每个片元**归一化，再比较 z，不能在顶点上提前判定正反面或仅插值 `normalZ` 的明暗值。

```glsl
precision highp float;
uniform sampler2D sTextureFront;
uniform sampler2D sTextureBack;
uniform sampler2D sTextureBack2;
uniform vec4 uColorScale;
uniform int sBackReverse;
varying vec3 vNormal;
varying vec2 vTexCoord;

void main() {
    vec3 normal = normalize(vNormal);
    if (normal.z > 0.1) {
        gl_FragColor = texture2D(sTextureFront, vTexCoord);
        gl_FragColor.rgb *= uColorScale.rgb;
    } else {
        vec2 texCoord = vTexCoord;
        if (sBackReverse != 0) {
            texCoord = vec2(1.0 - vTexCoord.x, vTexCoord.y);
        }
        vec4 back  = texture2D(sTextureBack,  texCoord);
        vec4 back2 = texture2D(sTextureBack2, texCoord);
        gl_FragColor = back * 0.05 + back2 * 0.95;
        gl_FragColor.rgb *= uColorScale.rgb;
        gl_FragColor.rgb *= 0.5 + abs(normal.z) * 0.5;
    }
}
```

[静态确认] `CS:SHADER_TEXTURE_FRAGMENT`

要点：

- 正反面分支由片元法线决定；纹理槽中是哪一页则由 `onDragStart` 决定；
- 单页背面是 **5% 被卷纸页 + 95% 背景**；双页背面两槽绑定同一邻页时，结果就是该完整邻页；
- 双页模式 `sBackReverse = 1`，背面纹理水平翻转；
- 单页模式 `sBackReverse = 0`，纸面的几何折返仍会改变显示朝向；
- 正面只乘 RGB colorScale，不做倾角压暗；背面才乘 `0.5 + |normal.z| * 0.5`，理论最暗为 50%。

顶点着色器只输出正交投影后的 `aPosition`，以及原样的 `aNormal/aTexCoord`，没有透视缩放或额外光照。[静态确认] `CS:8`。Flutter 可先在 CPU 做相同几何投影，再在片元中重建三角形的 UV 与完整法线插值；是否与原 GL 栅格化逐像素一致仍需比较。

[真机验证] 普通主题的 RGB565 输入由原 `CurlMesh`、原 GLSL 在 MEIZU 20 / Adreno 740 执行。受控多色色带确认：采样保留 RGB565 的高精度 UNORM 值；正面最终写回采用半精度最近偶数取整；纸背混色写回的端到端模型为半精度向零截断，随后光照乘法写回采用最近偶数取整。平直纸背 24 个色带均符合该模型。默认 lowp sampler 与显式 highp 返回值的 150 对探针逐位相同；不能把整段法线或混色表达式降成低精度。这里报告的是该 GPU 的观测模型，不断言内部寄存器的位置或其他 GPU 的取整方式。

### 7.2 阴影着色器

顶点着色器：

```glsl
uniform mat4 uProjectionM;
attribute vec3 aPosition;
attribute vec3 aPenumbra;
varying float vAlpha;
void main() {
    vec3 pos = vec3(aPosition.xy + aPenumbra.xy, aPosition.z);
    gl_Position = uProjectionM * vec4(pos, 1.0);
    vAlpha = aPenumbra.z;
}
```

片元着色器：

```glsl
precision highp float;
varying float vAlpha;
void main() {
    float alpha = vAlpha * 0.5;
    gl_FragColor = vec4(0.0, 0.0, 0.0, alpha);
}
```

[静态确认] `CS:SHADER_SHADOW_*`

阴影固定为黑色，alpha 沿三角形带插值后乘 0.5。半影是顶点位移形成的透明带，不是高斯模糊，也没有额外折痕描边。若 CPU 样本已经合并位移及 0.5 系数，绘制时不能再次乘同一系数。

[真机验证] 在同一手机、原阴影 GLSL、原 drop 几何下，受控 256 档透明度的未混合 RGBA8 输出及白底混合结果均符合：`a8 = floor(halfTrunc(vAlpha * 0.5) * 255 + 0.5) / 255`。例如 `vAlpha = 9/255` 输出 alpha 为 4，`vAlpha = 1` 输出 alpha 为 128。Flutter 在片元内完成该取整，避免先把顶点 alpha 转成 8 位再插值。原 GL 的混合函数同时作用于 framebuffer alpha，白底 alpha 会变为 `a8² + 1 - a8`；Flutter 的不透明阅读页保持 alpha 为 1，此处单独作为合成语义差异记录，RGB 对照不混入 alpha。

### 7.3 绘制顺序

每个 mesh：

```text
1. drop shadow（开混合）
2. 纹理正面/背面（关混合，直接覆盖）
3. self shadow（开混合）
```

所有 mesh 按 `mCurlMeshIndexs` 的加入序号升序绘制。[静态确认] `CR:120-185`

GL 状态：

```text
glClearColor(背景色)
glClear(GL_COLOR_BUFFER_BIT)
混合函数：GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
深度测试：关闭
背面剔除：关闭
```

[静态确认] `CR:120-215`

因为关闭深度测试，前后遮挡完全依赖 mesh 的加入顺序。DEX 的 `onDragStart` 各分支汇入同一个绑定段，按 **左静态页 → 右静态页 → 卷曲页**依次加入；左静态页或卷曲页锚点无效时跳过，右静态页锚点无效时使用背景。本次起手路径中的卷曲页最后绘制。[静态确认] `classes7.dex` 的 `:goto_1a8 → :cond_1dd → :goto_23e → :cond_294`；`CR:95-103、139-179`。

纸面和两类阴影都通过 `glDrawArrays(GL_TRIANGLE_STRIP, ...)` 绘制。纹理阶段关闭混合，直接覆盖缓冲；阴影阶段使用 `SRC_ALPHA / ONE_MINUS_SRC_ALPHA`。Flutter 的裁剪、透明合成和三角形公共边覆盖规则需要单独验证，不能只凭几何数值确认遮挡一致。

### 7.4 纹理参数

```text
GL_NEAREST        放大/缩小都最近邻
GL_CLAMP_TO_EDGE  边缘钳制
```

[静态确认] `CM:483-486`

最近邻采样不会为纹理提供双线性平滑。实际边缘锯齿、颜色台阶和像素相位还取决于位图量化、GPU 栅格化与 viewport，不能单凭此参数归因。

Flutter 的带 UV runtime shader 网格另有一条离屏路径：Impeller 先按 UV 覆盖绘制着色器快照，再采样到网格，默认二次采样器也是最近邻。低层证据为本地引擎 `vertices.cc:37-40`、`dl_vertices_geometry.cc:87-89`、`canvas.cc:83-94、1487-1490、1569-1583`。本轮保留原扫描网格，在投影最小截面拆为最多两段，按屏幕局部 x 反查纸面 x 和完整法线。纸面在完整视口矩形中逐片元判断原纸面/截面覆盖；阴影在各原三角形向外取整的矩形中使用半开公共边判断覆盖，并线性插值原 alpha。两者直接执行 runtime 片元路径，避免 UV 离屏采样和 MSAA 网格边缘混入底页，绘制顺序不变。

`duokan_curl.frag` 主入口保留覆盖、采样及半精度写回的线性顺序，作为超过 40 行的局部例外，便于直接核对原片元分支。修改或拆分该入口仍需复核像素与 FrameTiming；目前的色阶模型和性能证据只覆盖已编译执行的路径。

### 7.5 颜色缩放

`CurlPage.setColorScale(r, g, b)` 把三个分量限制在 `[0, 1]`，着色器对正面和背面都乘一次。[静态确认] `CP:82-86`

调用方可以调整 RGB scale；本次未验证主题/亮度变化时具体设置值和调用时序。

### 7.6 背面内容的正确预期

单页的纸背使用被卷纸页的固定 UV 与淡墨：

- 几何上使用同一组顶点和同一组 UV；
- 颜色上取 `5% 被卷纸页 + 95% 背景`；
- 明暗上按 `normal.z` 压暗。

由公式推断，单页纸背应接近背景色，并带有该纸页的淡墨；后退时淡墨来自上一页。双页不能套用这一观感，因为其背面两槽可能都是邻页图。[强结构推断]

单页预期：

```text
淡、近似纸色、能隐约看到一点背面透印、
随曲面弯曲而逐渐变暗、折痕处最暗。
```

不应该出现：

```text
图案位置漂移、文字比例忽大忽小、
局部被拉成长条、出现与纸张无关的直线分界。
```

上述症状需要分别检查 UV 映射、三角形连接、裁剪与片元法线插值，不能仅凭画面确定原因。原生扫描网格本来就会每帧重建，顶点数量从 18、36 到 46 的变化已由 oracle 确认；重建本身不意味着图案漂移。

## 8. 阴影模型

### 8.1 drop shadow

条件：

```text
0 < z <= r
```

参数：

```text
t = z / r
smooth = t² (3 - 2t)
penumbraOffset = sqrt(smooth) * r * 0.8 * (-direction)
alpha = smooth * 0.5 + 0.5
```

[静态确认] `CM:366-377`

这是**基点**的 alpha。乘片元系数后，基点理论范围为 `0.25 .. 0.5`；半影端点为 0，所以整条阴影带的范围是 `0 .. 0.5`，离散扫描未必采到理论最大值。

### 8.2 self shadow

条件：

```text
z > r
```

参数：

```text
t = (z - r) / r
smooth = t² (3 - 2t)
penumbraOffset = direction * smooth * r * 0.4
alpha = smooth * 0.3 + 0.3
```

[静态确认] `CM:379-391`

乘片元系数后，基点理论范围为 `0.15 .. 0.3`；半影端点为 0，整条阴影带范围是 `0 .. 0.3`。

### 8.3 顶点对

每个纸面顶点按 z 条件选为阴影基点，并插入各自轮廓数组的 `(size + 1) / 2` 位置，形成连续轮廓顺序。随后每项写入两个顶点：基点 `position、alpha`，端点 `position + penumbraOffset、alpha = 0`；最终统一作为连续 triangle strip 绘制。[静态确认] `CM:377、391、408-438`。

半径为 0 时纸面 z 为 0，两类阴影均为空。GL 的 viewport 会截去屏幕外部分，但这里没有把阴影按额外纸背轮廓路径裁剪。[静态确认] `CM:342-347、366-391`、`CR:142-178`。

### 8.4 已执行的阴影样本

400×600 页面中心拖动 120 像素时，纸面 36 顶点、drop shadow 36 顶点、self shadow 26 顶点：

| 样本 | 屏幕位置 | 最终 alpha |
|---|---|---:|
| drop 基点 0 | `(252.439880, 600)` | 0.250138 |
| drop 基点 18 | `(307.905884, 0)` | 0.495167 |
| drop 半影端点 35 | `(253.694031, 0)` | 0 |
| self 基点 0 | `(307.905884, 600)` | 0.152900 |
| self 半影端点 13 | `(265.927307, 0)` | 0 |

[数值验证] 此处“屏幕位置”是 Java oracle 换算出的页面像素坐标，不是截图。下角的轮廓顺序也有回归样本；GPU 插值、混合、公共边和裁剪的固定姿态对照见第 15 节。

## 9. 动效参数汇总

| 项 | 值 | 证据 |
|---|---|---|
| 起手动画时长 | `min(round(\|dxGL\| * 150), 100) ms` | `CPV:542-546` |
| 松手动画时长 | `max(round(\|dxGL\| * 150), 150) ms` | `CPV:280-282` |
| 插值 | smoothstep `t²(3-2t)` | `CPV:578-587` |
| 最大卷曲半径 | `pageWidth / 6` | `CPV:346-348` |
| 边缘自动翻页等待 | 50ms / 75ms | `CPV:612-640` |
| 页面提交 | 收尾动画结束后 | `CPV:560-575` |
| 网格段数 | 控件初始化 15；阅读器 `vf()` 确定设置 20 | `CPV:726`、`W:815-820` 及 DEX |
| 起拖距离 | 系统 `getScaledTouchSlop()`，另有方向与采样门槛 | `W:597-601`、`TG:55-77` |
| 20 的含义 | 甩动最低速度配置值，density 换算后用于 px/s 比较 | `W:603`、`FG:43-48、95-97` |

可参数化清单（新增类型时建议逐项显式定义，而不是散落常量）：

| 参数 | 多看取值 | 语义 |
|---|---|---|
| `radiusRatio` | `1/6` | 最大卷曲半径 / 页面宽 |
| `arcRatio` | `π` | 圆柱半周弧长 / 半径，也是 shift 分段点 |
| `startSnapRatio` | `1/3` | 距上下边缘多近吸附到边缘 |
| `startDurationMs` | `min(round(abs(dxGL) * 150), 100)` | 起手吸附动画 |
| `endDurationMs` | `max(round(abs(dxGL) * 150), 150)` | 松手收尾动画 |
| `quality` | 阅读器 20，控件初始化 15 | 扫描线段数 |
| `dropShadowScreenAlpha` | 整带 0–0.5，基点 0.25–0.5 | 投影最终透明度 |
| `selfShadowScreenAlpha` | 整带 0–0.3，基点 0.15–0.3 | 自阴影最终透明度 |
| `backInkRatio` | 0.05 | back 槽权重；单页槽中是被卷纸页 |
| `backDarkenFloor` | 0.5 | 背面最暗系数 |
| `frontThreshold` | 0.1 | `normal.z` 正面判定 |

## 10. 单页、双页与 RTL

已确认的组合维度：

```text
SHOW_ONE_PAGE  / SHOW_TOW_PAGE
RTL            / LTR
PAGE_UP        / PAGE_DOWN
```

[静态确认] `CPV:300-545`

已确认的行为：

- 双页时 `mMeshCurl.setBackReverse(1)`；
- 双页模式页面矩形按中心拆分；
- 单页 RTL 的起手侧与 LTR 相反；
- 三组 mesh 的纹理槽选择依赖上述组合。

本次未执行验证的部分：

- 首页/末页与不可用邻页时，外层是否接管、回退及完整画面；
- 双页时左右半页与相邻页绑定的运行画面；
- RTL 几何镜像、双页 backReverse 与像素采样的组合结果。

[未验证] `PIPE:6635-6655`、`PIPE:6760-6780`

## 11. 与排版引擎的边界

多看把边界切得很干净：

```text
native 排版
  -> 页对象、页锚点、页面几何
  -> DocPageView.draw(Canvas) 生成 Bitmap

Java 动画层
  -> PageProvider 取 Bitmap 和邻页锚点
  -> CurlPageView / CurlMesh 做几何与着色
  -> 动画结束后 flipPage() 提交
```

[静态确认] `PIPE:6740-6760`

因此：

- 排版器不需要知道当前是仿真、覆盖还是滚动；
- 动画层不解析 HTML，也不触发重新排版；
- 邻页预取上限是当前页 ±1；
- 位图格式、尺寸由排版层决定，动画层只消费。

## 12. 未闭合项

DEX 已闭合半径实参、越界缩减符号、角点排序、扫描求交、阅读器 20 段设置、单页前后纸页身份、起手边缘保留和逐帧 requestRender 链；这些不再作为反编译疑点。

仍需区分的运行边界：

1. 系统 slop、±50° 方向门槛、p1 起拖/p4 更新、20dp/s 快扫和起拖前多指取消已有公共回归；真机正文往返已执行。真实手指事件合并的完整时间轴，以及不同触控设备的采样节奏仍未同步对照。
2. 首页/末页、双页与 RTL 各组合的完整运行画面及外层接管路径。
3. Android Canvas 直接绘制 RGB565 与 Flutter 先绘制 RGBA 再还原 RGB565 色阶，正文抗锯齿、抖动及透明图层不保证逐像素等价。普通主题背景的分配 Config 已按源码核实；特殊主题的 ARGB8888 条件见第 3.2 节。
4. 原 GLSL 已在 Adreno 740 执行，半精度写回、RGB565 采样及阴影色阶已有受控证据；这些结果尚未覆盖其他 GPU。
5. 原 GL 与 Flutter 的最终像素覆盖及透明合成存在平台差异，固定姿态结果见第 15 节，不能据公式一致宣称全应用 1：1。
6. Flutter 真机 FrameTiming 已测量；原 GL 坐标时长已换算，但两款应用同一轨迹的完整触摸/vsync 时间轴尚未同步采集。
7. `Thread.sleep(50/75ms)` 的实际线程与掉帧影响。
8. 页码提交、纹理上传与位图缓存回收在并发运行中的时序。

Java 数值 oracle、原 GLSL 真机 oracle、Flutter GPU 探针和应用录像是四种不同证据；前者不执行图形 API，后面三者已实际执行。当前仍不能把局部验证扩大为整款阅读器或跨设备的逐像素 1：1。

## 13. 对新增仿真翻页类型的启示

这一节只给设计结论，不涉及代码修改。

### 13.0 与报告初始二维实现的能力对照

| 维度 | 多看 `THREE_DIMEN` | 报告初始基线 `simulationBessel` |
|---|---|---|
| 渲染 | `GLSurfaceView` + GLES 2.0 | Flutter `Canvas` + `drawVertices` |
| 几何 | 3D 半圆柱 + 背面折返 | 2D 贝塞尔折角 + 平面反射 |
| 网格 | 阅读器扫描 20 段，控件初始化 15 | 角部 4×4 顶点；侧边 34 顶点 |
| 纹理坐标 | 初始化时固定 0..1 | 固定，随反射矩阵变换 |
| 页面 | 单页 + 双页 | 单页 |
| 起卷区 | 上/下 1/3 吸附，中间 1/3 中心 | 仅屏高 5% 为中心区 |
| 收尾 | 约 150ms 起，smoothstep | 固定 420ms，easeOutCubic |
| 完成判定 | 非甩动释放 10dp 位移判定，甩动按速度方向 | 8% 页宽或速度阈值 |
| 提交时机 | 动画结束 | 动画结束 |
| 页面位图 | RGB_565 | RGBA，64 MiB / 6 张 |
| 邻页预取 | ±1 | ±2 |

此表保留报告初始二维实现的对照，不描述本轮 3D 版本。本轮几何、控制器、片元着色和真机运行的证据见第 6.9、7、15 节。

### 13.1 必须保留的契约

无论新增哪种仿真，以下五条不应改变：

1. **动画只消费位图**：输入是页面快照与页锚点，不进入排版。
2. **纹理坐标与顶点一一绑定**：内容附着在纸上，变形只改顶点位置。
3. **页码提交延迟到动画结束**：中途不改当前页锚点。
4. **邻页预取上限明确**：多看是 ±1，本项目当前是 ±2；新增类型要显式声明。
5. **取消与边界有明确出口**：首页/末页、反向甩动、外部跳转都要能回到原页。

### 13.2 两条实现路线

**路线 A：2D 顶点变形（Canvas）**

- 用固定 UV 的网格，顶点位置按翻页参数变形；
- 用 `Canvas.drawVertices` + `ImageShader` 绘制；
- 阴影用路径与渐变近似；
- 优点：无平台代码、与现有快照管线一致、可控；
- 缺点：没有逐像素光照，折痕的立体感靠渐变；
- 适合：折角、覆盖、平移、轻量仿真。

**路线 B：3D 网格 + 自定义着色**

- 顶点带 `(x, y, z)` 与法线；
- 正交投影后做半圆柱映射；
- 正反面按法线分支，阴影按 z 计算；
- 优点：接近多看的效果；
- 约束：Flutter 公共 API 没有可编程顶点着色器，但可以在 CPU 投影原生网格，再用 FragmentShader 重建三角形内的固定 UV 和完整法线插值；仅用顶点色近似无法完整复现片元内的 normalize 与 0.1 正反面分支。该路径的栅格化、裁剪与性能需要真机验证；
- 接入方式：独立几何/渲染类，共用现有页面快照、准备、取消和页码提交管线。

### 13.3 新增类型的接入点（建议）

本项目现有分层：

```text
PageTurnMode            模式枚举与持久化 id
PageTurnController      阶段、手势、进度、提交
PageTurnPainter         按模式分派绘制
PageTurnView            快照、预热、静态纸面恢复
PageSnapshotCache       位图预算与淘汰
```

新增一种仿真类型时，最小改动面应该是：

1. `PageTurnMode` 增加枚举项与中文名；
2. `PageTurnController` 增加该模式的进度映射与完成判定；
3. `PageTurnPainter` 增加一个绘制分支；
4. 复用现有快照、缓存、预热和提交逻辑；
5. 补该模式的几何单测与像素回归。

不应改动：

- `ReaderSession` 的页锚点与提交语义；
- 快照缓存的预算与淘汰；
- 其他模式的判定与时长。

### 13.4 防回归清单

固定 UV、有效的 strip 连接与正确片元插值是本次移植的回归边界：

1. **固定 UV**：同一个纹理坐标在任意拖动帧都对应同一张纸上的同一点；
2. **连接有效**：允许每帧扫描重新插点，但必须保持原生 strip 顺序；所有原 UV 三角形应完整覆盖页面且不越界；
3. **轮廓与内容同源**：纸背裁剪路径与网格顶点使用同一套几何；
4. **越界策略明确**：超出原图的采样要么延展边缘，要么裁掉，不能偷偷改变比例；
5. **连续帧一致性**：拖动 10 个阶段，取同一纸面点，屏幕位置应连续、无跳变；
6. **RTL 与单双页**：屏幕几何镜像与纸背 `backReverse` 是不同变换；单页后者为 0、双页为 1，各自按原契约应用，避免重复镜像。

### 13.5 建议的测试矩阵

| 维度 | 取值 |
|---|---|
| 方向 | 上一页 / 下一页 |
| 书写方向 | LTR / RTL |
| 起手区 | 上角 / 中部 / 下角 |
| 进度 | 0、0.1、0.25、0.5、0.75、0.9、1 |
| 结束方式 | 完成 / 回弹 / 反向甩动 / 外部跳转 |
| 页面类型 | 纯文字 / 整页图片 / 深色背景 / 画廊 |
| 数据状态 | 邻页已缓存 / 邻页未缓存 / 跨章 |

每个组合至少验证：

- 页码提交时机；
- 纸背内容是否固定；
- 是否露出底页或固定纸色；
- 是否出现直线分界、白带、拉伸；
- 轴是否与起手侧一致。

## 14. 关键证据索引

| 主题 | 位置 |
|---|---|
| 模式枚举 | `PageAnimationMode.java:1-22` |
| 模式到视图映射 | `RV:726-775` |
| 仿真层切换 | `W:687-701` |
| CurlPageView 懒加载 | `RV:642-649` |
| PageProvider 定义 | `PP:1-28` |
| PageProvider 实现 | `W:235-288` |
| 页面位图捕获与 RGB565 | `W:1012-1057`、`BM:110-112、387-388` |
| 背景分配格式与复制 | `o.java:4996-5010`、`W:824-829、1140-1145`、`BM:148-150、379-380` |
| 位图缓存 | `PIPE:6428-6455` |
| 三纹理槽与单页前后身份 | `CP:1-87`、`CPV:355-370、490-498`，DEX `onDragStart :goto_1a8` |
| 坐标转换 | `CR:252-257` |
| 页面矩形 | `CR:56-100` |
| 起手 | `CPV:300-545` |
| shift 与实际半径实参 | `CPV:195-234`，DEX `updateCurlPos` 的末次 invoke |
| 越界钳制与方向 | `CPV:98-179`，DEX `setCurlPos :cond_55/:cond_b9` |
| 起手页边保留上一帧 | `CPV:104-107、138-140` |
| 逐帧重绘链 | `CPV:180、234、550-557` |
| 松手与提交 | `CPV:267-290`、`CPV:560-575` |
| 边缘自动翻页 | `CPV:612-640` |
| 系统起拖距离与采样 | `W:597-601`、`TG:55-77、143-164`、`MK:1133-1134` |
| 20 配置的是甩动速度 | `W:603`、`FG:43-48、95-97`、`GC:43-44` |
| 松手 10dp 位移分支 | `W:548-584` |
| 固定纹理坐标 | `CM:203-216`、`CM:534-556` |
| 扫描线与圆柱映射 | `CM:219-360` |
| 背面折返 | `CM:338-350` |
| 阴影生成与轮廓排序 | `CM:366-438` |
| 阴影着色器 | `CS:5-6` |
| 纹理着色器与片元法线 | `CS:7-8` |
| 绘制顺序 | `CR:120-185` |
| GL 状态 | `CR:188-215` |
| 纹理参数与上传 | `CM:476-498` |
| 网格质量 | `W:815-820`、`CPV:653-668` |
| 数值验证 | 第 6.9 节的 Dart 回归与 Java oracle |
| 未闭合项 | 本文第 12 节 |

关键原文件可直接复核：

- [CurlPageView：shift、页边保留及纹理绑定](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlPageView.java:98)
- [CurlMesh：扫描、法线与阴影缓冲](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlMesh.java:219)
- [CurlStatic：原 GLSL](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/fi/harism/curl/CurlStatic.java:5)
- [平移检测器：系统 slop 与采样](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/ui/i.java:55)
- [甩动检测器：最低速度](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/ui/b.java:43)
- [页面与背景位图来源](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/reader/ui/reading/w.java:1012)
- [Bitmap 分配与复制](/Users/aaa/Documents/demo/Spectacular/参考/duokan/reverse/jadx/sources/com/duokan/core/utils/a.java:110)

## 15. 当前验证边界

[真机验证] 本轮在 MEIZU 20 / Android 16 / Adreno 740 上执行原多看 7.44.21、原 `CurlMesh`/GLSL 的 GLES 离屏参照、Flutter Impeller Vulkan 探针及本项目正式 Release。探针为独立包，复用本地依赖与冻结源码；探针快照、图像、录像、日志和 APK 保存在 `/tmp`。

固定像素对照为 400×600、相同素材、相同姿态：下角、水平、近水平上角/下角和上一页五组姿态各含纯色/2 像素黑竖线，另有两个 24 色带案例，共十二组。RGB 按字节比较；原 GL framebuffer alpha 与 Flutter 不透明页面的合成语义不同，单独记录。

- [像素对照] 最终五组纯色和两组色带的最大单通道差均为 1；水平纯色/标记图的平均绝对 RGB 误差为 0.0100/255，两个色带为 0.0064/255、0.0061/255。
- [像素对照] 原先 horizontal 的 x261 整列 600 像素有明显误差；最终纯色/标记图均整列精确，RGB 为 `[141,134,130]`。x195、199、200、219、250、260、262 的整列也精确。
- [像素对照] 标记图仍有 21 个像素的单通道误差超过 1：corner 7 个黑/红纹理边界交换，upper/lower 各 2 个最大差 9，previous 10 个最大差 13。不能把这些差异描述成全部只是末位色阶，也不能宣称逐像素 1：1。
- [数值验证 + 真机对照] 原 Float32 顶点的连续覆盖与原 GPU 纸面 alpha，在五姿态共 120 万像素上零差；删除两条最小投影同列桥后仍零差。强制按 1/16 像素取整产生 27 处覆盖差，未引入该取整。

性能使用正式 `PageTurnView`/控制器与合成正文、逻辑视口 384×787.2、DPR 2.8125、四张快照占 38,257,920 字节。24 个热缓存前后/上中下窗口，从起手帧统计至提交后的静态承接帧，排除初始化、图像导出和预热。使用 Flutter `FrameTiming`，百分位采用 nearest rank；不使用 `gfxinfo` 推断 Flutter 帧率。

| 本项目渲染阶段 | 帧数 | build P50/P95/峰值（ms） | raster P50/P95/峰值（ms） |
|---|---:|---|---|
| 优化前逐三角形离屏 | 736 | 0.697 / 1.288 / 4.121 | 16.290 / 23.100 / 34.966 |
| 最终片元覆盖 | 737 | 1.047 / 1.856 / 5.290 | 16.507 / 17.063 / 32.989 |

raster P95 降低 26.13%。设备上报约 120Hz，但实测 vsync 间隔主要约 16.2ms；按 60Hz 的 16.667ms 预算，最终 raster 超预算 196 帧，连续 vsync 缺口估计 16。P95 仍超预算约 0.396ms，不能宣称全程无掉帧。这里比较的是本项目优化前后，未把原多看的帧率作为已测数据。

[验证] ReaderUI 全量 733 项、核心背景/绘制 16 项通过；最后覆盖修正另复测几何/着色器/绘制 27 项通过。UI、mobile 与本轮 core 改动静态分析均无问题，`git diff --check` 通过。

[真机验证] 正式 arm64 Release 使用 `flutter --no-pub` 与 Gradle `--offline` 构建成功，已覆盖安装 `com.spectacular.reader_mobile` 1.0.0，APK SHA256 为 `42f6e0083fed944b317f0240732c75fcb549f6b243d81602afde20028c642851`。真机《游戏入侵》第 5 章的十页正文，3D 模式下中心、上角、下角前后翻页已执行，页码按 `6→7→6→7→6` 正常落页。

本轮证据入口：[探针复现说明](/tmp/spectacular-curl-gpu-probe/复现说明.md)、[最终像素报告](/tmp/spectacular-curl-gpu-probe/results/mask_rgb.json)、[帧耗时与采样汇总](/tmp/spectacular-curl-gpu-probe/results/mask_summary.json)、[余差坐标](/tmp/spectacular-curl-gpu-probe/results/mask_remaining_pixels.json)、[原 GL 与数值核验](/tmp/spectacular-duokan-half-review/README.md)、[正式版录像](/tmp/spectacular-duokan-release-final.mp4)。临时证据可能在系统清理 `/tmp` 后丢失；可维护的数值/公共行为回归保存在仓库测试中。

范围仍限普通单页仿真。其他 GPU、特殊 ARGB8888 背景、双页模式、全组合 RTL、冷缓存/跨章压力与不同排版引擎的完整页面，没有由这些固定素材和热缓存测量证明等价。
