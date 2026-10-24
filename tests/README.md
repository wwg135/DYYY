# UI 布局回归

此前全屏回归包为 `2.2-9-22+fullscreen.22`，全屏协调器加载标记为 `fullscreen-viewport-20261023.22`。
真机环境：iPhone XR、iOS 16.0、RootHide，抖音 40.7.0（407019）。
仓库原有 36.5.0 适配说明保持有效；这里记录本次局部 UI 修改的验证范围。

## 本次行为

- 全屏观看按钮的位置交给抖音原生布局；移除协调器中的按钮查找、定位和碰撞隐藏。
- 播放器按稳定 Feed cell 的窗口坐标修正预加载缓存，避免开评论时视频移出屏幕。
- 毛玻璃模式拦截媒体位移，评论主体及复用文字背景跟随开关恢复；图文继续使用原来的分支。

## 本地检查

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos make package SCHEME=roothide PACKAGE_VERSION=2.2-9-22+fullscreen.22
clang -fobjc-arc -framework Foundation -framework CoreGraphics -I . DYYYFullscreenGeometry.m tests/FullscreenGeometryTests.m -o /private/tmp/dyyy-fullscreen-geometry-tests
/private/tmp/dyyy-fullscreen-geometry-tests
```

以上打包和几何测试均通过。测试覆盖视口裁剪、横竖视频等比适配、Feed 预加载平移、评论拖动、重复计算以及无效输入。
Deb 已通过 SSH 安装，并终止/重开目标 App 校验加载标记；安装后差异仅为已解析的 RootHide 品牌字段 8 字节及代码签名 32 字节，其他载荷字节一致。

## 真机观察

- 横屏视频：从图文页滚动进入后，评论开关一轮通过。毛玻璃开启时媒体矩形不变，关闭后恢复；77 次动画过渡采样的文案向下偏移最大为 0，互动层高度保持 827 pt，18 个评论文字控件背景透明。
- 全屏观看按钮：上述开关前、开关中、关闭后的窗口矩形均为约 `(171, 529.2, 72, 25.6)`，保持可见。
- 图文：连续打开/关闭评论 3 轮，三次打开时各 17 个文字控件均无残留背景；随后继续观察约 39 秒，目标进程不变，完整测试约 78 秒。
- 另一次计划 6 轮的连续测试完成 4 轮后，原生动作未找到可见目标，随后调试连接中断；这组不计为完整通过。
- 上述操作使用已经核验 ABI 的 App 内原生动作和 UIKit Feed 滚动，不能视为物理触摸轨迹测试。

历史回归中曾出现 App 退出和 Frida 链路中断。已观察到 Frida daemon 的 `OS_REASON_JETSAM`，这只能证明该调试服务被系统终止，不能据此认定 App 退出原因。本次短回归不代表长期稳定性或其他抖音版本兼容；本版竖屏 Live 图文的完整回归仍需单独覆盖。

## 2026-10-24 资源与性能修复

- 定时器析构同步释放内部资源，不再提交捕获已析构对象的回调。
- 普通媒体、批量图片和实况照片共用流式下载会话，最多同时下载 3 个文件；文件移动在后台，进度刷新限制为每秒最多 10 次。
- 每次下载、每组实况转码使用独立文件和状态。取消保留终止回调入口，批次只完成一次；实况转码与静态图片编码按生命周期串行调度。
- 清屏仅在进入或配置改变时扫描窗口，后续使用弱引用实例缓存，布局刷新在同一轮主队列中合并。弹幕输入背景复用并跟随毛玻璃开关恢复。
- 全局 UIView Hook 增加开关及几何快速路径；视频编码使用写入就绪回调，失败或长期无进度会退出并释放资源。

本地命令：

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos CLANG_MODULE_CACHE_PATH=/private/tmp/dyyy-audit-module-cache make package SCHEME=roothide
clang -fobjc-arc -fblocks -framework Foundation -I . AWMSafeDispatchTimer.m DYYYDownloadScheduler.m tests/AsyncResourceTests.m -o /private/tmp/dyyy-async-resource-tests
/private/tmp/dyyy-async-resource-tests
python3 tests/run_pipeline_regressions.py
```

打包、异步资源测试、原有几何测试均通过；异步资源测试也通过 AddressSanitizer 检查（未启用泄漏扫描）。
管线测试从生产源文件提取下载和编码方法，使用本机回环 HTTP、生成的 PNG/视频验证文件隔离、下载并发、HTTP 错误、等待/活跃任务取消、批次迟到回调、图片视频编码、两组实况图片/视频 UUID 一致以及失败后队列恢复。测试仅监听 `127.0.0.1`，结束后关闭服务器并清理生成文件；实测最大下载并发为 3。

管线测试中的 CGImage 和 Toast 适配不模拟 UIKit 布局，也不调用相册保存。最初 XR 的设备信息和 UI 读取均返回 SSH `ConnectionLost`；恢复连接后的安装与检查记录如下。上面的历史真机记录属于此前的全屏版本。

## 2026-10-24 XR 补充回归（资源修复包）

重新执行并通过以下构建，再通过已配置的 SSH 转发安装；此前的 `.deb` 和设备原注入文件均已保留：

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos CLANG_MODULE_CACHE_PATH=/private/tmp/dyyy-audit-module-cache make package SCHEME=roothide PACKAGE_VERSION=2.2-9-23+resources.1
```

- 设备：iPhone XR、iOS 16.0、RootHide；抖音 `40.7.0 (407019)`。使用已有的 Frida `17.5.0` 隔离客户端匹配设备，恢复本机 `27043` 转发，没有更换设备端 Frida。
- 安装版本：`2.2-9-23+resources.1`。包 SHA-256 为 `adee4198f7f95a241a2086d35308b114d6ea0814682f5f3ab8c0eb2016b42f00`，传输前后相同。
- 安装后的 dylib 与本地 staged dylib 逐字节相同，SHA-256 为 `5b4078fb7c668f5e46f2df75ec3bde15933f0d328d1d4ba512f1c317d3be6bfe`。通过新下载方法的实际 IMP 核对到进程加载的 arm64e UUID `2227EB2A-AD9E-3A46-8DF2-F1144B246B5E`，与该构建一致。
- 新进程 PID `40351`：Feed 向下、向上各滚动一次，UIKit 操作均成功并回到原偏移；这不能单独证明下一条视频完整播放。
- 用户手动打开评论后，评论列表上下滚动均成功；主体毛玻璃在滚动前后两次采样中均为一层，透明度约 `0.9`，矩形约 `(0, 286.72, 414, 609.28)`。滚动前后全窗口效果视图均为 5 个，没有观察到数量增长。这里仅覆盖一轮打开/关闭及列表复用，没有覆盖旧版弹幕输入控件分支。
- 用户手动关闭评论后，截图恢复为 Feed；全屏观看入口矩形约 `(171, 529.2, 72, 25.6)`，与关闭评论前相同；互动层高度保持 `827 pt`，进程仍为 PID `40351`。
- 评论入口和关闭按钮没有可用的 UIKit target/action，自动化返回也不能关闭这个嵌入式面板，因此该轮开关由用户操作，滚动通过 UIKit 自动化完成。

旧进程 PID `35865` 在本轮最初挂载时返回恢复进程失败，并留下 `2026-10-24 14:39:31 +0800` 的 dyld `SIGTRAP` 记录；该记录单独保留，触发原因未确定。后续加载检查及以上 UI 操作使用新进程 PID `40351`。

尚未覆盖：关闭毛玻璃开关后的材质恢复、清屏浮窗（当前未开启）、iOS 相册保存、并发实况在真机上的完整流程，以及 CPU/内存/帧率定量测量。不能用这次基础 UI 回归替代这些专项检查。

## 2026-10-24 悬浮按钮显示协调

显示判断集中到 `DYYYFloatingButtonCoordinator`。按实际选中 Tab、导航栈、评论面板、纯净模式和前后台状态计算两个按钮的可见性；清屏状态也不能越过页面限制。Tab 选中和根页面替换主动刷新，布局只登记弱引用并合并刷新；移除多处共享显示标志、通过普通视图透明度猜测评论状态的逻辑，以及页面切换时固定 0.5 秒的清屏点击阻塞。按钮外观仅在配置变化时更新。

本地验证均通过：

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos CLANG_MODULE_CACHE_PATH=/private/tmp/dyyy-audit-module-cache make package SCHEME=roothide PACKAGE_VERSION=2.2-9-24+floating.2
clang -fobjc-arc -fblocks -framework Foundation -framework CoreGraphics -I tests/support -I . DYYYFloatingButtonCoordinator.m tests/FloatingButtonVisibilityTests.m -o /private/tmp/dyyy-floating-visibility-tests
/private/tmp/dyyy-floating-visibility-tests
```

测试直接编译生产协调器，使用最小 UIKit 夹具验证 256 种显示条件、缓存 Tab 往返、导航选择、迟到回调、多个评论面板、纯净模式、模态遮挡、清屏、前后台和配置关闭；连续 100 次无配置变化的刷新不会重算标题。夹具不验证真实 UIKit 布局和动画。原有全屏几何测试通过；已有全局 UIView 和全屏 frame 处理与本次修改前逐字节一致。

XR 最终包 `2.2-9-24+floating.2` 已安装并核对加载，设备和 App 环境同上：

- 包 SHA-256：`28fcfbcdd78cfb880055c3095e0af7f11034e8c7b5d354eb0aff843cda918f48`。设备注入文件与 staged dylib 相同，SHA-256 为 `29f067ee67e9612395104a34f8efc61a5469705d3d073ea81a75af38476dfda1`，加载的 arm64e UUID 为 `3A21E24A-27E2-3C18-AA19-C8681F193B77`。
- PID `42685` 使用已核验 ABI 的原生 Tab 点击接口完成 3 轮普通“首页 → 消息 → 首页”和 1 轮清屏往返。每次进入消息页两个按钮均隐藏；普通返回时两个按钮均在原生点击接口返回时恢复，清屏返回时保留清屏退出入口并按设置隐藏倍速。退出清屏后两个按钮恢复。
- 全程复用同一播放控制器、倍速按钮和清屏按钮，位置保持不变。操作结束恢复首页及非清屏状态，没有更改用户设置，临时追踪已解除。
- 这里验证的是运行时可见性和原生动作，未测物理点击到屏幕呈现的延迟或帧率，也未在本轮重新执行真实评论、纯净模式的开关流程。

详细运行记录：`/private/tmp/dyyy-floating-xr-regression-20261024.json`。资源修复包及两版悬浮按钮包均保留；设备上一版文件备份位于 `/tmp/DYYY-rollback-floating-20261024-2-28fcfbcd`。

## 2026-10-24 设置搜索主题适配

搜索框复用抖音原生动态色 `BGInput`、`TextPrimary`、`TextQuaternary`、`Link`，分别用于背景、文字、占位/图标和光标。按抖音自身主题设置键盘及搜索框子树的 UIKit 外观；监听实测的 `AWEUIThemeChangeNotification`，主线程刷新并在释放时取消监听。页面返回及布局保留主题校验，主题未变化时跳过设色。缺少原生颜色接口时使用对应色值回退。

以下构建通过，产生 arm64/arm64e dylib 和 RootHide 包：

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos CLANG_MODULE_CACHE_PATH=/private/tmp/dyyy-audit-module-cache make package SCHEME=roothide PACKAGE_VERSION=2.2-9-24+searchdark.3
```

- XR 安装版本 `2.2-9-24+searchdark.3`，包 SHA-256 为 `c35ef0d3f9132734c6ca52b931dbe83d7cc13e9e43f771fe63159bbe77f4d56d`；设备与 staged dylib 的 SHA-256 均为 `5676a788d67d5224a9a331834d17c60a7bd88ba372b069f1d179856772e70444`。通过新方法 IMP 核验 PID `43494` 加载的 arm64e UUID 为 `ABA2A736-6565-3D0F-B3BC-F5D002E91C99`。
- 抖音深色、UIKit 上层浅色时，搜索框保持深色；空闲占位、输入占位、搜索结果及原生清除按钮动作通过检查。搜索“倍速”得到 10 项，清除后恢复 12 项根设置。
- 保持输入状态切为抖音浅色后，背景、文字、占位、两个搜索图标、光标、键盘及搜索框子树外观同步更新。无匹配查询返回 0 项，清空并结束输入后恢复居中占位；通过 UIKit 导航离开后切为深色再返回，外观正确。
- 每步实际色值与抖音原生动态色逐项一致。测试使用已核验签名的原生主题接口、UIKit 控件动作和导航操作；结束恢复原有深色主题及颜色方案，关闭键盘，清空查询并卸载临时 Frida 脚本。覆盖设备和 App 版本同上，不代表其他版本或长期稳定性验证。

详细运行记录：`/private/tmp/dyyy-searchdark-xr-regression-20261024.json`。旧安装包及设备文件备份均保留。

## 2026-10-24 推送前同步与检查

以远端 `main` 的 `6bdc7c3` 为基准整合此批修改，保留远端 29 个提交。重叠的搜索主题实现统一为原生动态配色与主题通知；倍速保留远端的配置归一化，显示状态使用协调器；清屏使用弱引用缓存，并复用远端的原始状态捕获和恢复方法，避免恢复后残留捕获标记。

以下构建通过：

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos CLANG_MODULE_CACHE_PATH=/private/tmp/dyyy-audit-module-cache make package SCHEME=roothide PACKAGE_VERSION=2.2-9-24+sync.1
```

同步后的几何、异步资源、悬浮按钮和媒体管线回归全部重新执行并通过，回环 HTTP 实测最大并发仍为 3。另外提取生产清屏快照方法与缓存恢复方法，通过临时 macOS 夹具检查普通视图、原本隐藏的视图和动态暂停图标各 3 轮恢复，验证原始 alpha/hidden 保留、捕获标记释放与重复恢复无副作用。

本次 `sync.1` 包仅完成本地构建和上述回归，没有安装到 XR；上文真机记录对应各自标注的构建版本。

## 2026-10-24 创作者主页全屏与分页修复

推荐页保留全屏协调器，其他来源恢复原有布局分支。创作者主页（`others_homepage`）单独调整原生基础底部边距，使列表视口与真实 cell 行高共同铺满屏幕；移除仅将列表 frame 向上取整的 Hook。若 UIKit 已缓存旧行高，在页面布局/出现且停止滚动时重新询问原生行高，并按原视频索引恢复分页。正常行高直接跳过更新，另有重入保护。互动层以固定评论输入栏的位置确定底边，避免复用后重复减去底部高度。

以下构建和原有全屏几何测试通过：

```sh
GITHUB_ACTIONS=true THEOS=/Users/vita/theos CLANG_MODULE_CACHE_PATH=/private/tmp/dyyy-audit-module-cache make package SCHEME=roothide PACKAGE_VERSION=2.2-9-24+sync.4
clang -fobjc-arc -framework Foundation -framework CoreGraphics -I . DYYYFullscreenGeometry.m tests/FullscreenGeometryTests.m -o /private/tmp/dyyy-fullscreen-geometry-tests
/private/tmp/dyyy-fullscreen-geometry-tests
```

- XR 环境：iOS 16.0、RootHide、抖音 `40.7.0 (407019)`，保留 Frida `17.5.0`。修改前实际观察到列表视口与缓存行高混用 `827/896 pt`，首条返回后文案上移 `69 pt`；只调整视口会让评论输入栏下方露出下一条视频。
- 接入自动刷新前，使用相同的原生行高缓存更新操作进行运行时验证：7 条视频、向下 6 次再向上 6 次 UIKit 动画翻页，13 次采样均通过。真实 cell 与分页步长均为 `896 pt`，互动层为 `827 pt`，当前 cell 在窗口中从 `y=0` 开始；同一条视频复用后的文案、左右互动区位置一致，截图未再出现下一条视频提前露出。
- 最终包 `2.2-9-24+sync.4` 已安装并重启 App；加载标识为 `fullscreen-creator-native-20261024.2`，arm64e UUID 为 `E41618B6-55E7-39F1-A577-0A6819118A29`。包 SHA-256 为 `a274926a6b751c018d03b94124ffc7f8eea92fbfa3fd88d29aafb23e7b7fdf9c`。用户随后实测确认没有问题，授权更新；上述 12 次自动翻页属于接入前的运行时验证，未在最终包上重复执行。

本轮覆盖创作者视频 cell 复用与固定评论输入栏，不代表横屏、键盘展开或所有内容来源的完整回归。详细截图、行高和布局记录保存在本机 `/private/tmp/dyyy-xr-fullscreen-debug/`。


## 2026-10-24 通用详情页与图文评论边界

原生详情列表按控制器结构统一处理基础底部边距、分页缓存及固定底栏，覆盖创作者主页、观看历史及共享该结构的入口。关闭评论毛玻璃时，视频与图片使用状态栏下沿到实际评论面板顶部的可用区域；图片按真实图片内容范围等比缩放，并缓存关闭态以恢复布局。

`make package SCHEME=roothide PACKAGE_VERSION=2.2-9-24+sync.10` 和几何测试通过；几何测试补充整图、带留白和不居中图片的边界。XR 用户确认观看历史视频铺满、底部输入栏透明和当前图片效果可以；图片自动验证中的“实际尺寸与理论最大尺寸误差小于 0.6 pt”断言未通过，因此没有把自动开关评论两轮记为通过。一次自动翻页也捕到了未对齐的中间状态，未计入通过记录。失败日志保留在本机 `/private/tmp/dyyy-image-final/report.json` 与 `/private/tmp/dyyy-xr-fullscreen-debug/detail-regression-history/report.json`。
