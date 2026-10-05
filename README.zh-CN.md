# AnchoredOverlayKit

[English](README.md) · [简体中文](README.zh-CN.md)

面向 iOS 的锚定菜单与可展开面板，支持 UIKit 和 SwiftUI。从编辑器的 **+** 打开菜单，切换二级页面，再把内容添加到草稿，同时保留键盘焦点。

库负责展示、布局、材质、裁切和过渡；应用提供内容、选中状态和业务操作。

- 页面导航时保留视图、局部状态及滚动位置。
- 独立选择内容布局、缩放和页面过渡效果。
- iOS 26+ 使用系统 Liquid Glass，旧系统回退到系统模糊材质。
- 沿弹层实时圆角补齐贴边项目的选中描边。
- 将内容动画收进目标视图，并协调从系统界面返回后的恢复。

**环境要求：iOS 16+、Swift 6.2、Xcode 26+。** 无第三方运行时依赖。以下示例使用 **0.3.1** API。

[演示](#演示) · [安装](#安装) · [快速入门](#快速入门) · [页面组合](#页面组合) · [贴边选中描边](#贴边选中描边) · [API 文档](docs/API.zh-CN.md)

## 演示

打开菜单 → 展开照片 → 选择两张 → 添加到草稿 → 继续输入。

![输入框与照片面板连续演示](https://github.com/rien7/anchored-overlay-kit/releases/download/0.3.1/overlay-showcase-preview-0.3.1-1f5e9aa0567a.gif)

[观看或下载完整视频](https://github.com/rien7/anchored-overlay-kit/releases/download/0.3.1/overlay-showcase-0.3.1-e214b87b516b.mp4)。在 iOS 26.4 模拟器上连续录制，以 1 倍速播放。示例使用内置照片，可离线运行；贴边选中框使用 `OverlayBoundaryHighlighting`。

打开 [Examples/OverlayDemo.xcodeproj](Examples/OverlayDemo.xcodeproj)，选择 **Showcase** 即可体验。可运行代码见 [ShowcaseController.swift](Examples/OverlayDemo/ShowcaseController.swift) 和 [RecentPhotosDemo.swift](Examples/OverlayDemo/RecentPhotosDemo.swift)。

## 安装

| 应用 | 安装方式 | 包提供的内容 |
| --- | --- | --- |
| UIKit / SwiftUI | Swift Package Manager | 原生库产品。 |
| React Native / Expo | npm + CocoaPods | 原生模块使用的 Swift 源码；桥接由应用提供。 |

### Swift Package Manager

在 Xcode 中选择 **File → Add Package Dependencies**，输入仓库地址，选择 **0.3.1** 或更新版本：

```text
https://github.com/rien7/anchored-overlay-kit.git
```

使用 Package.swift 时添加：

```swift
.package(url: "https://github.com/rien7/anchored-overlay-kit.git", from: "0.3.1")
```

在 target 的 dependencies 中加入 `.product(name: "AnchoredOverlayKit", package: "anchored-overlay-kit")`。

### npm + CocoaPods / Expo

```sh
pnpm add @rien7/anchored-overlay-kit
```

在应用 Podfile 的 target 中添加：

```ruby
package_json = Pod::Executable.execute_command('node', [
  '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json", { paths: [process.argv[1]] })',
  __dir__
]).strip
pod 'AnchoredOverlayKit', :path => File.dirname(package_json)
```

使用方原生模块还需在 podspec 中声明 `s.dependency 'AnchoredOverlayKit', '~> 0.3.1'`。运行 `pod install` 后重新构建原生应用。同一 target 选择一种安装方式。

npm 包提供 **Swift 原生源码**，不包含 JavaScript 组件或自动 React Native 桥接。Expo 项目应在 prebuild 前将 pod 写入持久化应用配置，参考 [Expo 接入示例](INTEGRATION.md#expo-prebuild)。需要原生构建或 development build；Expo Go 无法加载本库。

## 快速入门

在编辑器开始输入**之前**创建并持有 controller，每个编辑器使用一个实例。触发视图必须已经加入当前活动窗口。内容提供内部间距与控件，controller 提供外层材质和裁切。

### UIKit

将以下成员加入已有视图控制器，在按钮操作中调用 `showMenu(from:)`：

```swift
import UIKit
import AnchoredOverlayKit

private let overlay = AnchoredOverlayController()

private func showMenu(from button: UIView) {
  let metrics = OverlayControlMetrics()
  let menu = OverlayMenuContent(items: [
    .init(title: "Close", systemImage: "xmark") { [weak self] in
      self?.overlay.dismiss()
    },
  ], metrics: metrics)

  overlay.present(
    content: menu, anchoredTo: button,
    layout: .init(width: .fixed(280), height: .content(max: 360)),
    appearance: .init(cornerRadius: metrics.menuRadius),
    dismissLabel: "Close menu"
  )
}
```

将菜单项替换为你的业务操作。菜单和容器共用 `metrics.menuRadius`，可保持圆角对齐。所属控制器移除时调用 `overlay.cancel()`。完整编辑器与按钮布局见 [Showcase 示例](Examples/OverlayDemo/ShowcaseController.swift)。

### SwiftUI

```swift
import SwiftUI
import AnchoredOverlayKit

@MainActor
struct InsertButton: View {
  @State private var overlay = AnchoredOverlayController()

  var body: some View {
    OverlayButton(
      controller: overlay,
      layout: .init(width: .fixed(260), height: .content(max: 300)),
      accessibilityLabel: "Insert", dismissLabel: "Close menu"
    ) {
      Image(systemName: "plus")
    } content: {
      VStack(alignment: .leading, spacing: 16) {
        Text("Insert into your draft")
        Button("Done") { overlay.dismiss() }
      }
      .padding(20)
    }
    .frame(width: 44, height: 44)
    .onDisappear { overlay.cancel() }
  }
}
```

保持 controller 和视图身份稳定，状态变化会更新已挂载的内容及其自然高度。`.disabled(true)` 会关闭该按钮持有的弹层。`OverlayMenuButton` 为固定尺寸的 SF Symbol 提供便捷入口。

## 页面组合

`OverlayPages` 使用同一个容器，按 ID 保留页面。在同一个 owner 中，用已有 controller 创建：

```swift
private lazy var pages = OverlayPages(
  controller: overlay, transitionStyle: .blurredCrossfade
)
```

在对应的按钮操作中调用以下代码，`makeMenu()` 和 `makePhotoGrid()` 是应用自己的视图构造函数：

```swift
let menu = OverlayPage(
  id: "menu",
  layout: .init(width: .fixed(280), height: .content(max: 360)),
  appearance: .init(cornerRadius: 40),
  contentScaling: .fit
) { [weak self] in self?.makeMenu() ?? UIView() }
pages.present(menu, anchoredTo: plusButton, dismissLabel: "Close attachments")

let photos = OverlayPage(
  id: "photos",
  layout: .expandingToBottom(inset: 12),
  appearance: .init(corners: .bottomConcentric(top: 24, fallback: 24))
) { [weak self] in self?.makePhotoGrid() ?? UIView() }
pages.push(photos)

// In the secondary page's Back action:
pages.back()
```

返回时保留页面状态和滚动位置，整个弹层关闭后才释放。如果选择结果需要跨关闭保留，应存入应用模型。保留的页面工厂及操作闭包应弱引用 owner，参考 [Showcase 示例](Examples/OverlayDemo/ShowcaseController.swift)。

内容布局与视觉动效可以分别选择：

| 策略 | 默认值 | 其他选择 |
| --- | --- | --- |
| 页面上的 `contentLayout` | `.stable`：按目标尺寸布局，通过裁切逐步显现。 | `.viewport`：按弹层当前可见尺寸布局。 |
| 页面上的 `contentScaling` | `.none`：保持内容原有尺寸。 | `.fit`：将已布局的内容缩放到变化中的面板内。 |
| `OverlayPages` 的 `transitionStyle` | `.sequentialFade` | `.crossfade` 或 `.blurredCrossfade` |

演示中菜单启用缩放，照片网格保持不缩放。正文缩放时，`OverlayPageChrome` 仍保持原有尺寸。`.spring` 和 `.immediate` 控制过渡时序。“减弱动态效果”会让几何立即变化并禁用缩放；“减弱动态效果”或“降低透明度”会禁用模糊。完整约定见 [页面动效](docs/API.zh-CN.md#页面动效)。

## 贴边选中描边

**0.3.0 新增：** 内容通过 `OverlayBoundaryHighlighting` 提供需要沿面板圆角继续描边的区域。库的高亮渲染使用弹层实时裁切几何，并跟随滚动和转场更新。

在传给 `present` 或由 `OverlayPage` 工厂返回的 UIKit 内容视图上实现协议。例如，应用自己的照片网格可以这样写：

```swift
extension PhotoGridView: OverlayBoundaryHighlighting {
  var overlayBoundaryHighlights: [OverlayBoundaryHighlight] {
    selectedVisibleImageViews.map { imageView in
      OverlayBoundaryHighlight(
        view: imageView, clippedTo: collectionView,
        color: tintColor, lineWidth: 3
      )
    }
  }
}
```

这里的 `selectedVisibleImageViews` 来自选中模型和当前可见单元格。颜色与线宽应和项目本身的边框一致。应用绘制项目边框与编号，库补齐**这些区域内沿面板边界的描边**；视口只限制覆盖范围，不会新增一圈边框。

只返回当前可见的选中视图，getter 内不修改布局。无需推算面板圆角、创建遮罩、添加滚动回调或手动失效通知。项目自身有圆角时可指定 `shape: .roundedRect(radius:)`。SwiftUI 内容需要提供实现该协议的 UIKit 包装视图。完整选项与限制见 [边界高亮](docs/API.zh-CN.md#边界高亮)。

## 布局与控件

### 调整面板大小

```swift
overlay.update(
  layout: .bottomEdge(inset: 12, height: .viewportFraction(0.6)),
  appearance: .init(corners: .bottomConcentric(top: 24, fallback: 24))
)
```

`.viewportFraction(0.6)` 使用源窗口高度的 60%，最终受可用空间限制。`.expandingToBottom()` 保留上一页顶部并向底部展开；`.bottom(inset:)` 从安全区计算距离，`.bottomEdge(inset:height:)` 从窗口边缘计算。

iOS 26+ 中，底部及左右等间距的面板可以使用系统解析的同心圆角。触发最大宽度限制、位于键盘上方或运行于旧系统时，使用 fallback 圆角。UIKit 内容通过 Auto Layout 或 `OverlayContentSizing` 提供自然高度，变化后调用 `invalidateContentSize()`。可滚动页面需要有界高度。完整说明见 [布局与外观](docs/API.zh-CN.md#布局与外观)。

### 添加悬浮操作按钮

通过 `OverlayPageChrome` 返回前景控件层，使用 `OverlayActionBar` 排列返回、添加及可选的中间操作。将 `OverlayContentSafeArea` 的回调传给 `safeAreaClearance`，使用 `contentBottomInset` 给滚动内容预留控件空间。

```swift
let back = OverlayActionButton()
back.appearance = .clearGlass(backingColor: .black.withAlphaComponent(0.6))
back.configuration?.image = UIImage(systemName: "chevron.left")
back.accessibilityLabel = "Back"
```

`actionStyle` 表达操作的强调程度，`appearance` 决定材质和底色。主要操作使用 `.emphasized` 与 `accentColor`；底色绘制在玻璃下面，`.automatic` 恢复默认外观。另见 [按钮外观](docs/API.zh-CN.md#按钮外观) 和 [照片网格示例](Examples/OverlayDemo/RecentPhotosDemo.swift)。

## 目标收起与生命周期

| 任务 | API | 应用负责的部分 |
| --- | --- | --- |
| 动画收进附件缩略图 | `dismiss(to:representation:cornerRadius:destinationVisibility:completion:)` | 先接受内容到模型并挂载目标，提供尚未挂载的独立 representation 视图。 |
| 等待权限弹窗或系统选择器 | `performExternalInteraction`，使用 `.inApp` | 执行操作，并在主 actor 调用完成回调。 |
| 从设置返回 | `performExternalInteraction`，使用 `.leavingApp` | 提供所属 presenter、有效性检查和需要恢复的页面，沿用原始 scene。 |
| 移除编辑器 | `cancel()` | owner 移除时取消；页面转为非活动状态时停止相机和订阅。 |

目标收起动画在完成回调前恢复目标原有的 alpha。目标不存在、移出屏幕或开启“减弱动态效果”时回退到淡出。`OverlayPageActivity` 独立于视图缓存报告页面活动状态。另见 [关闭与取消](docs/API.zh-CN.md#关闭与取消)、[外部交互](docs/API.zh-CN.md#外部交互) 和 [内容协议](docs/API.zh-CN.md#内容协议)。

## 键盘兼容性

在编辑开始前创建 controller。库保留编辑焦点，并尝试覆盖可用的键盘宿主；通过 `placementState` 查看实际展示位置。设置 `allowsKeyboardOverlap: false`，可让弹层留在应用窗口中。

键盘覆盖依赖 UIKit 未文档化的 `UIRemoteKeyboardWindow` 类名，相关逻辑集中在 [KeyboardOverlayHost.swift](Sources/AnchoredOverlayKit/KeyboardOverlayHost.swift)。没有调用私有 selector，也不改变 key window。无法可靠识别宿主时，库回退到应用窗口并避让键盘。请验证应用支持的设备、键盘及 scene 组合，参考 [接入约束](INTEGRATION.md#ownership-and-constraints)。

## 示例与文档

克隆仓库后打开 [Examples/OverlayDemo.xcodeproj](Examples/OverlayDemo.xcodeproj)。**Showcase** 展示上述流程，其他页面覆盖 UIKit / SwiftUI 菜单、动态尺寸、保留状态的页面及生命周期行为。照片网格使用内置图片，系统选择器示例会打开真实系统界面。

| 资料 | 内容 |
| --- | --- |
| [API 文档](docs/API.zh-CN.md) | 签名、默认值、结果与生命周期约定。 |
| [接入指南（英文）](INTEGRATION.md) | CocoaPods、Expo 及应用接入。 |
| [验证记录（英文）](VALIDATION.md) | 检查与运行时证据。 |
| [录制说明](docs/media/README.md) | 连续演示录制方法与较早的 Lody 录屏。 |
| [发布说明（英文）](PUBLISHING.md) | npm 与 Swift Package 分发。 |

提交贡献时，请附上可运行示例，并执行与修改相关的检查：

```sh
python3 scripts/verify.py
python3 scripts/verify.py --scenario pages --output .artifacts/pages-acceptance
npm run verify:distribution
```

模拟器检查需要 Xcode、iOS runtime、Python 3、AXe 和 ffmpeg/ffprobe，可按需设置 `DEVELOPER_DIR`。分发检查从实际 npm 压缩包构建正常签名的 CocoaPods 与 SPM 宿主。[Lody iOS](https://github.com/Innei/lody-ios) 是参考接入应用。

## 许可证

[MIT](LICENSE)。
