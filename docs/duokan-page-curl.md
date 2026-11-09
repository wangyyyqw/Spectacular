# 多看仿真翻页资料报告

> 目的：完整梳理多看阅读 7.44.21 的仿真翻页实现，为后续在本项目新增一种仿真翻页类型提供事实基础。
>
> 对象：`参考/duokan/多看_7.44.21.apk`（包名 `com.duokan.reader`，versionCode 744210000）
>
> 方法：JADX 反编译源码、APK 资源、ELF 符号与字符串静态分析。未运行 APK，未做动态 Hook。
>
> 本文只记录静态可读事实与有边界的推断，不修改任何代码。

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
15. [一句话总结](#15-一句话总结)

## 0. 阅读约定

全文用三级证据标记：

```text
[静态确认]   反编译源码、类关系、常量、调用链可直接读出。
[强结构推断] 由位置计算、着色器公式和对象用途共同支持，但没有逐帧对照。
[未验证]     JADX 输出存在重复块、语义丢失或常量可疑，不能据此宣称像素级等价。
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
```

## 1. 结论摘要

1. 仿真翻页是**独立动画层**，不进入 native 排版。[静态确认]
2. 实现是 `GLSurfaceView` + OpenGL ES 2.0，三组 `CurlMesh`（左静态页、卷曲页、右静态页/背景），每组三张纹理。[静态确认]
3. 卷曲页的几何是**页面矩形 → 旋转 → 扫描线求交 → 半圆柱映射 → 背面折返**；纹理坐标只在初始化时设置一次，之后不随拖动改变。[静态确认]
4. 页面内容来自 `DocPageView.draw(Canvas)` 生成的 **RGB_565** 位图；双页模式按左右半页裁剪。[静态确认]
5. `CurlMesh` 的正面/背面切换不看页面锚点，只看顶点法线 `normal.z > 0.1`；背面颜色是 `back * 0.05 + back2 * 0.95`，再按 `0.5 + |normal.z| * 0.5` 压暗。[静态确认]
6. 阴影是独立几何：drop shadow 覆盖 `0 < z <= r`，self shadow 覆盖 `z > r`；顶点对成对写入，着色器统一乘 0.5。[静态确认 + 强结构推断]
7. 起手在页面上/下三分之一内会吸附到边缘，否则进入中心模式；中心模式强制 `y = pageCenterY`，形成竖直折痕。[静态确认]
8. 最大卷曲半径 `r = pageRect.width() / 6`；拖动距离到 `πr` 时半径为 0，超过后半径转负，页面完成翻折。[静态确认]
9. 起手有 100ms 吸附动画，松手有 `max(|dx| * 150, 150) ms` 的 smoothstep 收尾；页码提交发生在收尾动画结束后。[静态确认]
10. 反编译层存在若干不可逐行还原的分支（尤其起手邻页选择、`onDragMove` 的帧请求），复刻应以“结构与契约”为准，而不是逐行照抄。[未验证]

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

[静态确认] `PIPE:6400-6418`

三个直接后果：

- 位图是**页面最终外观**，包含正文、图片、装饰；
- 位图尺寸与当前排版一致，动画层不做缩放决策；
- RGB_565 是刻意的内存选择，代价是渐变可能出现色带。

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

`CurlPageView.onDragStart` 的绑定语义：

```text
左侧静态 mesh:  整页纹理，setBitmap(bitmap, 4)
右侧静态 mesh:  有邻页则整页；否则背景图，setBitmap(background, 4)
卷曲 mesh:      front = 当前卷曲页
                有另一邻页时 back = 该页，back2 = 该页
                否则 back = front，back2 = 背景图
```

[静态确认] `CPV:420-470`

文档明确标注：具体哪一页进入哪个槽取决于单页/双页、RTL 和拖动方向，反编译分支无法逐行无歧义还原；可确认的是**槽位语义**，不是每种组合的唯一页号。[未验证] `PIPE:6635-6655`

### 3.5 一次翻页的完整时序

```text
触摸
  -> W.j 判定方向与 10dp 阈值
  -> CurlPageView.onDragStart
       -> 取当前页与前后邻页锚点
       -> 取页面位图 / 背景位图
       -> 三组 mesh 绑定纹理与页面矩形
       -> 100ms 起手动画
  -> onDragMove 更新指针
  -> onDrawFrame -> updateCurlPos -> setCurlPos -> CurlMesh.curl
  -> 松手 onDragEnd
       -> 计算 target 与 duration
       -> smoothstep 收尾
       -> 动画结束 flipPage(direction)
       -> afterFlip(false)
       -> PageProvider 刷新阅读状态与页面缓存
```

[静态确认] 各步位置见第 5 节；帧循环中的 `requestRender` 缺口见 5.3。

### 3.6 位图到纹理的交接

```text
PageProvider.getPageBitmap(anchor)
  -> CurlPage.setBitmap(bitmap, slot)
  -> CurlMesh.getTextures()
       -> 首次：glGenTextures(3)
       -> 位图变化：GLUtils.texImage2D × 3
       -> 上传完成：mPage.recycle() 清空 Bitmap 引用
```

[静态确认] `CM:459-490`、`CP:40-70`

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

不调用 `requestRender()`。[静态确认] `CPV:288-296`

`onDrawFrame` 在非动画状态下调用 `updateCurlPos(mPointerPos)`。[静态确认] `CPV:545-560`

这与 `RENDERMODE_WHEN_DIRTY` 存在矛盾：如果拖动期间没有其它路径请求重绘，画面不会连续更新。复刻时必须自建帧调度，不能照搬这段调用关系。[未验证] `PIPE:6510-6518`

### 5.4 卷曲半径

```text
R = pageRect.width() / 6
arc = πR
distance = |pointer - anchor|

distance >= arc:  radius = -(distance - arc) / 2
distance > 0:     radius = sqrt(arc * distance) - distance
distance == 0:    radius = 0
```

[静态确认] `CPV:219-234`

特点：

- `distance` 在 `arc/4` 附近半径最大（约 `arc/4`），随后减小；
- 到 `arc` 时半径为 0；
- 超过 `arc` 后半径为负，页面开始真正翻到另一侧。

### 5.5 越界钳制

`setCurlPos` 在指针越过页边时：

```text
半径按越界距离线性减小：
  radius' = max(radius - (越界距离 * 1.05 * 2) / π, 0)
指针拉回页边
```

同时修正方向向量，避免指针与页边的交点越出页面上下边界。[静态确认] `CPV:96-160`

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

`W.j` 的常量：

```text
n = 20     拖动 slop（dp）
p = 10     翻页判定阈值（dp）
q = 50
```

[静态确认] `W:369-374`

`J(view, z)` 里设置：

```text
g.d0(2)              // 手势识别参数
h.d0(F(view, 20))    // slop 20dp
g.g0(-50), f0(50)    // 速度范围
```

[静态确认] `W:594-606`

`H(view, event, ...)` 的规则：

```text
若仿真层不可接管：直接结束
若指针数 > 1：结束（多指取消）
若正在动画或存在未完成手势：拒绝新的拖动
释放时：
  threshold = F(view, 10)
  根据累计位移 j.x 与 threshold 的关系，决定 ReleaseDirection 的符号
  调用 onDragEnd(point, ±1 方向)
```

[静态确认 + 强结构推断] `W:524-586`

外层做的是“10dp 位移 → 方向符号”的转换；`CurlMesh` 层再比较这个符号与起手方向。两层合起来的效果是：**朝翻页方向拖动超过约 10dp，松手即完成**，属于方向主导，而不是按页宽比例判定。

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
translate(-touch.x, -touch.y)
rotateZ(-acos(direction.x))     // direction.y > 0 时取负角
```

[静态确认] `CM:225-245`

旋转后按 `x` 排序，得到最左、最右顶点，用于确定扫描线范围。

### 6.3 扫描线

```text
d18 = π * radius
scanLines = [0]
for i = 1 .. splits-1:
    scanLines.add(-d18 * i / (splits - 1))
scanLines.add(最右顶点.x - 1)
```

[强结构推断] `CM:266-286`

`splits` 来自 `mMaxCurlSplits`。构造默认 15，阅读器运行时通常为 20（见 6.7）。扫描线数量约 `splits + 1`。

### 6.4 交点与顶点序列

对每条扫描线：

```text
遍历旋转后的四个顶点
  若顶点 x 落在当前扫描线范围内：
    取相邻边求交
    交点继承顶点纹理坐标
  按 y 顺序组织成上下两条边
```

[强结构推断] `CM:286-330`

JADX 输出把排序和临时数组复用混在一起，逐行含义不可靠；可确认的是“扫描线与矩形求交、按 y 排序、交点插值纹理坐标”这一结构。[未验证]

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

按 `r = 180`（1080 宽的 1/6）、`arc = πr ≈ 565` 估算：

| 拖动距离 | 半径 | 形态 |
|---:|---:|---|
| 0 | 0 | 未起卷 |
| 141（arc/4） | 约 141 | 半径最大 |
| 282（arc/2） | 约 117 | 继续收卷 |
| 565（arc） | 0 | 卷到极限 |
| > 565 | 负值 | 页面翻到另一侧 |

这是公式推算，不是实机测量。[强结构推断]

### 6.6 背面折返

最后一条扫描线单独处理：

```text
mPosX = -(mPosX + πr)
mPosZ = 2r
n = (0, 0, -1)
penumbraX = -penumbraX
```

[静态确认] `CM:338-350`

这条线把纸背“翻”到 `z = 2r` 的平面，并水平镜像，形成纸背的起始边。

### 6.7 网格质量

构造：

```text
mMaxCurlSplits = max(1, quality)
顶点缓冲容量 = splits * 2 + 6
```

[静态确认] `CM:110-150`

阅读器计算：

```text
F = round(screenRGB565Bytes * (twoPage ? 4 : 2) / 1MB)
maxMemory / totalMemory / freeMemory（MB）
quality = round(pow((F/max) * (free/total) * (1 - total/max), qx0.l) * 12 + 8)
```

[静态确认] `W:815-820`

`qx0.l` 当前为 `0.0`，`pow(x, 0) = 1`，所以静态结果是 `round(12 + 8) = 20`。但构造器默认是 15，两者不一致，属于待复核常量。[未验证] `PIPE:6672-6690`

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

## 7. 着色与合成

### 7.1 纹理着色器

```glsl
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
```

[静态确认] `CS:SHADER_TEXTURE_FRAGMENT`

要点：

- 正反面只由 `normal.z` 决定，与页码、锚点无关；
- 背面不是“另一张完整页”，而是 **5% 邻页 + 95% 背景**；
- 双页模式 `sBackReverse = 1`，背面纹理水平翻转；
- 背面按法线倾角压暗，最暗为 50%。

### 7.2 阴影着色器

```glsl
// vertex
pos = aPosition.xy + aPenumbra.xy
vAlpha = aPenumbra.z

// fragment
alpha = vAlpha * 0.5
color = vec4(0, 0, 0, alpha)
```

[静态确认] `CS:SHADER_SHADOW_*`

阴影几何不带颜色，最终固定黑色半透明，alpha 再乘 0.5。

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

因为关闭深度测试，前后遮挡完全依赖 mesh 的加入顺序。`onDragStart` 在不同起手分支里添加左、右、卷曲 mesh 的先后并不固定，因此“卷曲页一定在最上层”不能作为通用结论。[未验证] 复刻时如果改用有深度的渲染器，需要重新定义顺序，而不是照搬加入顺序。

### 7.4 纹理参数

```text
GL_NEAREST        放大/缩小都最近邻
GL_CLAMP_TO_EDGE  边缘钳制
```

[静态确认] `CM:466-480`

这解释了翻页边缘的硬采样和锯齿，也意味着背景渐变可能出现台阶。

### 7.5 颜色缩放

`CurlPage.setColorScale(r, g, b)` 把三个分量限制在 `[0, 1]`，着色器对正面和背面都乘一次。[静态确认] `CP:70-80`

阅读器用它做主题色/亮度适配。

### 7.6 背面内容的正确预期

多看的背面不是“另一张独立页面”，而是同一张纸翻过去后的反面：

- 几何上使用同一组顶点和同一组 UV；
- 颜色上取 `5% 邻页 + 95% 背景`；
- 明暗上按 `normal.z` 压暗。

所以正常观感应当是：

```text
淡、近似纸色、能隐约看到一点背面透印、
随曲面弯曲而逐渐变暗、折痕处最暗。
```

不应该出现：

```text
图案位置漂移、文字比例忽大忽小、
局部被拉成长条、出现与纸张无关的直线分界。
```

出现后者，通常是纹理坐标被二次重采样，或者网格拓扑每帧重建。[强结构推断]

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

[静态确认] `CM:365-385`

最终着色器再乘 0.5，所以屏幕 alpha 约 `0.25 .. 0.5`。

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

[静态确认] `CM:386-405`

最终屏幕 alpha 约 `0.15 .. 0.3`。

### 8.3 顶点对

每个阴影顶点写入两次：一次在原始位置，一次在偏移后的位置；两次的 alpha 和半影不同，形成从边缘到透明的渐变带。[静态确认] `CM:405-430`

## 9. 动效参数汇总

| 项 | 值 | 证据 |
|---|---|---|
| 起手动画时长 | `min(\|dx\| * 150, 100) ms` | `CPV:542-546` |
| 松手动画时长 | `max(\|dx\| * 150, 150) ms` | `CPV:280-282` |
| 插值 | smoothstep `t²(3-2t)` | `CPV:578-587` |
| 最大卷曲半径 | `pageWidth / 6` | `CPV:346-348` |
| 边缘自动翻页等待 | 50ms / 75ms | `CPV:612-640` |
| 页面提交 | 收尾动画结束后 | `CPV:560-575` |
| 网格段数 | 15（默认）/ 20（公式） | `CPV:726`、`W:815-820` |

可参数化清单（新增类型时建议逐项显式定义，而不是散落常量）：

| 参数 | 多看取值 | 语义 |
|---|---|---|
| `radiusRatio` | `1/6` | 最大卷曲半径 / 页面宽 |
| `arcRatio` | `π` | 半径归零时的拖动距离 / 半径 |
| `startSnapRatio` | `1/3` | 距上下边缘多近吸附到边缘 |
| `startDurationMs` | `min(abs(dx) * 150, 100)` | 起手吸附动画 |
| `endDurationMs` | `max(abs(dx) * 150, 150)` | 松手收尾动画 |
| `quality` | 15 或 20 | 扫描线段数 |
| `dropShadowScreenAlpha` | 0.25–0.5 | 投影最终屏幕透明度 |
| `selfShadowScreenAlpha` | 0.15–0.3 | 自阴影最终屏幕透明度 |
| `backInkRatio` | 0.05 | 背面邻页透印比例 |
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
- 双击模式页面矩形按中心拆分；
- 单页 RTL 的起手侧与 LTR 相反；
- 三组 mesh 的纹理槽选择依赖上述组合。

无法逐行还原的部分：

- 首页/末页时 `nextPageAnchor` / `prevPageAnchor` 返回 null 的具体分支；
- 双页时左右半页与相邻页的对应关系；
- RTL 下背面水平翻转与邻页选择的组合。

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

以下问题在文档中被明确标注，复刻时不能当作已知：

1. `onDragStart` 在首页、末页、双页、RTL 下的邻页与纹理槽选择；
2. `CurlMesh` 的扫描线数组、交点排序是否与上游 Harism CurlView 完全一致；
3. `quality` 公式中 `qx0.l = 0.0` 是否符合真实运行逻辑；
4. `onDragMove` 没有显式 `requestRender`，连续帧由谁驱动；
5. `setCurlPos` 中 1.05 系数和 `2/π` 半径缩减的完整符号方向；
6. `Thread.sleep(50/75ms)` 的实际线程与掉帧影响；
7. 不同 GPU 上的采样、混合和阴影边缘是否一致；
8. 双击/双页模式下的页面矩形与纹理对应关系；
9. `CurlPage` 三槽在实际运行中的回收时机；
10. 外层手势 `W.j` 的分支在 RTL 与末页下的完整语义。

[未验证] `PIPE:6760-6782`

## 13. 对新增仿真翻页类型的启示

这一节只给设计结论，不涉及代码修改。

### 13.0 与当前项目的能力对照

| 维度 | 多看 `THREE_DIMEN` | 本项目当前 `simulationBessel` |
|---|---|---|
| 渲染 | `GLSurfaceView` + GLES 2.0 | Flutter `Canvas` + `drawVertices` |
| 几何 | 3D 半圆柱 + 背面折返 | 2D 贝塞尔折角 + 平面反射 |
| 网格 | 扫描线 15/20 段 | 角部 4×4 顶点；侧边 34 顶点 |
| 纹理坐标 | 初始化时固定 0..1 | 固定，随反射矩阵变换 |
| 页面 | 单页 + 双页 | 单页 |
| 起卷区 | 上/下 1/3 吸附，中间 1/3 中心 | 仅屏高 5% 为中心区 |
| 收尾 | 约 150ms 起，smoothstep | 固定 420ms，easeOutCubic |
| 完成判定 | 约 10dp 方向主导 | 8% 页宽或速度阈值 |
| 提交时机 | 动画结束 | 动画结束 |
| 页面位图 | RGB_565 | RGBA，64 MiB / 6 张 |
| 邻页预取 | ±1 | ±2 |

此表只用于定位差距，不代表当前项目必须逐项对齐。[静态确认] 多看侧见前文；本项目侧来自当前源码。

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
- 缺点：Flutter 公共 API 没有可编程顶点着色器；`drawVertices` 只能做顶点色近似，真正的逐像素光照需要平台视图或引擎层支持；
- 适合：作为独立实验，不应与主阅读链路耦合。

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

上一轮角部曲面出现“纸背内容随拖动游动”，根因是改了纹理采样而不是顶点。新增类型必须通过以下检查：

1. **固定 UV**：同一个纹理坐标在任意拖动帧都对应同一张纸上的同一点；
2. **拓扑稳定**：网格的连接关系不随视口、包围盒或拖动距离重建；
3. **轮廓与内容同源**：纸背裁剪路径与网格顶点使用同一套几何；
4. **越界策略明确**：超出原图的采样要么延展边缘，要么裁掉，不能偷偷改变比例；
5. **连续帧一致性**：拖动 10 个阶段，取同一纸面点，屏幕位置应连续、无跳变；
6. **RTL 与单双页**：镜像只作用于几何或纹理之一，不能同时翻两次。

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
| 页面位图捕获 | `PIPE:6400-6418` |
| 位图缓存 | `PIPE:6428-6455` |
| 三纹理槽 | `CP:1-87`、`CPV:420-470` |
| 坐标转换 | `CR:252-257` |
| 页面矩形 | `CR:56-100` |
| 起手 | `CPV:300-545` |
| 半径公式 | `CPV:219-234` |
| 越界钳制 | `CPV:96-160` |
| 松手与提交 | `CPV:267-290`、`CPV:560-575` |
| 边缘自动翻页 | `CPV:612-640` |
| 外层阈值 | `W:369-374`、`W:524-606` |
| 固定纹理坐标 | `CM:203-216`、`CM:534-556` |
| 扫描线与圆柱映射 | `CM:219-360` |
| 背面折返 | `CM:338-350` |
| 阴影生成 | `CM:365-430` |
| 阴影着色器 | `CS:SHADER_SHADOW_*` |
| 纹理着色器 | `CS:SHADER_TEXTURE_*` |
| 绘制顺序 | `CR:120-185` |
| GL 状态 | `CR:188-215` |
| 纹理参数 | `CM:466-480` |
| 网格质量 | `W:815-820`、`CPV:653-668` |
| 未闭合项 | `PIPE:6760-6782` |

## 15. 一句话总结

多看的仿真翻页不是“把一张图做透视”，而是**先把纸张离散成带固定 UV 的顶点带，再让顶点在三维空间里绕圆柱卷曲**；正反面、阴影、颜色都由顶点法线和 z 值决定。复刻时最应该保留的是这条“几何变形、纹理不动”的原则，而不是某一组具体公式。
