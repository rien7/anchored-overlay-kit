# AnchoredOverlayKit

[English](README.md) · [简体中文](README.zh-CN.md)

从输入框的 **+** 打开菜单，再展开成照片网格或相机面板。整个过程沿用同一个连续变化的容器，键盘保持打开。

AnchoredOverlayKit 是面向 iOS 的 UIKit / SwiftUI 库，负责弹层的位置、尺寸、系统玻璃材质、圆角和页面过渡。内容和业务行为由你的应用提供。

- 在可用的键盘宿主上覆盖键盘，同时保留编辑焦点。
- 切换菜单和二级页面时保留视图、页面状态及滚动位置。
- iOS 26 及以上默认使用系统 Liquid Glass，旧系统回退到系统模糊材质。
- 将选中的内容动画收进目标视图，例如输入框里的附件缩略图。
- 协调权限弹窗和前往设置后的恢复，避免过期回调重新打开弹层。

**环境要求：iOS 16+、Swift 6.2、Xcode 26+。** 无第三方运行时依赖。

[安装](#安装) · [UIKit 入门](#uikit-入门) · [SwiftUI](#swiftui) · [常见用法](#常见用法) · [全部 API 参数](docs/API.zh-CN.md) · [详细接入说明（英文）](INTEGRATION.md)

## 效果视频

以下是 [**Lody iOS**](https://github.com/Innei/lody-ios)（[Lody](https://github.com/LodyAI/Lody)） 接入本库后的演示。照片加载、选择、相机拍摄和编辑器附件属于应用业务，并非库内置组件。

**照片：** 从菜单展开网格、切换布局、选择照片，再动画添加到草稿。

![照片菜单动态预览](https://raw.githubusercontent.com/rien7/anchored-overlay-kit/main/docs/media/photos-preview.gif)

<details>
<summary>观看完整视频</summary>

https://github.com/user-attachments/assets/e3288620-ad88-46c9-ae85-749ba4e518ba

</details>

**相机：** 展开取景器、重新拍摄、将照片添加到草稿。

![相机展开动态预览](https://raw.githubusercontent.com/rien7/anchored-overlay-kit/main/docs/media/camera-preview.gif)

<details>
<summary>观看完整视频</summary>

https://github.com/user-attachments/assets/59b63b54-1145-40c7-9fe5-cc145b221bec

</details>

录制环境为 iOS 26.4 模拟器，Lody 提交 `3b582f0`，视频以 1.5 倍速播放。相机使用固定测试画面，不是真机摄像头画面。

## 安装

### Swift Package Manager

在 Xcode 中选择 **File → Add Package Dependencies**，输入：

```text
https://github.com/rien7/anchored-overlay-kit.git
```

选择 **0.2.0** 或更新版本，将 **AnchoredOverlayKit** 产品加入应用 target。使用 Package.swift 时添加：

```swift
.package(url: "https://github.com/rien7/anchored-overlay-kit.git", from: "0.2.0")
```

并在使用方 target 的 dependencies 中加入 `.product(name: "AnchoredOverlayKit", package: "anchored-overlay-kit")`。

### npm + CocoaPods / Expo

```sh
pnpm add @rien7/anchored-overlay-kit
```

npm 包提供的是 **Swift 原生源码**，不提供 JavaScript 组件或自动 React Native 桥接。在应用 Podfile 的 target 中添加：

```ruby
package_json = Pod::Executable.execute_command('node', [
  '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json", { paths: [process.argv[1]] })',
  __dir__
]).strip
pod 'AnchoredOverlayKit', :path => File.dirname(package_json)
```

如果从原生模块中导入本库，还需要在该模块的 podspec 中声明 `s.dependency 'AnchoredOverlayKit', '~> 0.2.0'`。运行 `pod install` 后重新构建原生应用。同一 target 选择 CocoaPods 或 SPM 其中一种方式。

Expo 项目应把 extra pod 写进持久化的 app config，再执行 prebuild，参考 [Expo 接入示例](INTEGRATION.md#expo-prebuild)。Expo Go 无法加载本库。

## UIKit 入门

在编辑器开始输入**之前**创建并持有 controller。触发按钮必须已经加入当前活动窗口。下面是可以改造成输入框附件入口的完整小示例：

```swift
import UIKit
import AnchoredOverlayKit

@MainActor
final class EditorViewController: UIViewController {
  private let overlay = AnchoredOverlayController()
  private let plusButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
    plusButton.accessibilityLabel = "Attachments"
    plusButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(plusButton)
    NSLayoutConstraint.activate([
      plusButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      plusButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
      plusButton.widthAnchor.constraint(equalToConstant: 44),
      plusButton.heightAnchor.constraint(equalToConstant: 44),
    ])
    plusButton.addAction(UIAction { [weak self] _ in self?.showMenu() }, for: .touchUpInside)
  }

  private func showMenu() {
    let metrics = OverlayControlMetrics()
    let menu = OverlayMenuContent(items: [
      .init(title: "Insert text", systemImage: "text.badge.plus") { [weak self] in
        self?.overlay.dismiss { [weak self] in self?.insertText() }
      },
      .init(title: "Close", systemImage: "xmark") { [weak self] in
        self?.overlay.dismiss()
      },
    ], metrics: metrics)
    overlay.present(
      content: menu, anchoredTo: plusButton,
      layout: .init(width: .fixed(280), height: .content(max: 360)),
      appearance: .init(cornerRadius: metrics.menuRadius),
      dismissLabel: "Close attachments"
    )
  }

  private func insertText() { /* Update your editor here. */ }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    overlay.cancel()
  }
}
```

库负责外层材质和裁切，内容负责内部间距及控件。菜单与容器共用 `metrics.menuRadius`，图标圆盘就能与菜单圆角按同心圆公式对齐。

## SwiftUI

```swift
import SwiftUI
import AnchoredOverlayKit

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

保持 controller 和视图身份稳定。状态变化会更新已挂载的内容，自然高度也会自动重新测量。`.disabled(true)` 会关闭该按钮持有的弹层。只需要固定尺寸的 SF Symbol 按钮时，可以使用 `OverlayMenuButton`。

## 常见用法

### 从一级菜单展开到二级页面

使用 `OverlayPages` 保持连续容器。以下片段放在同一个 owner 中，`makePhotoGrid()` 是应用自己的网格构造函数：

```swift
// Stored properties on the owning view controller:
private let overlay = AnchoredOverlayController()
private lazy var pages = OverlayPages(controller: overlay)

// Open the root menu:
let menu = OverlayPage(
  id: "menu",
  layout: .init(width: .fixed(280), height: .content(max: 360)),
  appearance: .init(cornerRadius: 40)
) { [weak self] in
  OverlayMenuContent(items: [
    .init(title: "Recent photos", systemImage: "photo.on.rectangle") { [weak self] in
      self?.showPhotos()
    },
  ])
}
pages.present(menu, anchoredTo: plusButton, dismissLabel: "Close attachments")

// In showPhotos(), return your own grid from makePhotoGrid():
pages.push(OverlayPage(
  id: "photos",
  layout: .expandingToBottom(inset: 12),
  appearance: .init(corners: .bottomConcentric(top: 24, fallback: 24))
) { [weak self] in self?.makePhotoGrid() ?? UIView() })

// Back button:
pages.back()
```

页面按 ID 缓存，整个弹层关闭后才释放。返回时保留局部状态和滚动位置；如果选择结果需要跨关闭保留，应将它存放在应用模型中。相机取景器可以设置 `contentLayout: .viewport`，随动画中的可见尺寸布局；默认 `.stable` 则让文字和网格按目标尺寸布局，通过容器裁切逐步显现。

### 调整大小、圆角和材质

```swift
let layout = OverlayLayout.bottomEdge(
  inset: 12, height: .viewportFraction(0.6), maxWidth: 600
)
let appearance = OverlayAppearance(
  corners: .bottomConcentric(top: 24, fallback: 24),
  background: .glass(.regular)
)
overlay.update(layout: layout, appearance: appearance)

// Other backgrounds:
let tinted = OverlayAppearance(background:
  .glass(.clear, tint: .systemBlue.withAlphaComponent(0.12)))
let blur = OverlayAppearance(background: .material(.systemMaterial))
let solid = OverlayAppearance(background: .color(.secondarySystemBackground))
```

`.viewportFraction(0.6)` 表示源窗口高度的 60%，最终仍受可用空间限制。`.expandingToBottom()` 保留上一页顶部并向底部展开；`.bottom(inset:)` 从安全区底部计算距离，`.bottomEdge(inset:height:)` 从窗口边缘计算。

iOS 26 及以上，在底部及左右等间距时，可以由系统解析设备同心圆角：`内圆角 = max(0, 外圆角 − 间距)`。触发最大宽度限制、边距不等、位于键盘上方或运行于旧系统时使用显式 fallback。顶部圆角由应用设置。

UIKit 内容尺寸变化后调用 `overlay.invalidateContentSize()`，并通过 Auto Layout 或 `OverlayContentSizing` 提供自然高度。可滚动页面需要有界高度。完整选项见 [布局与外观](docs/API.zh-CN.md#布局与外观)。

### 将照片动画收进输入框

```swift
// First accept the media into your model and mount its destination thumbnail.
let preview = UIImageView(image: selectedImage)
preview.contentMode = .scaleAspectFill
preview.clipsToBounds = true

overlay.dismiss(
  to: attachmentThumbnail, representation: preview,
  cornerRadius: 8, destinationVisibility: .hideDuringTransition
) { result in
  // The library restores the thumbnail's original alpha before this callback.
  // Observe .dismissed / .superseded / .cancelled / .notPresented here.
}
```

先将媒体接受到应用模型并挂载目标缩略图，再提供一个尚未挂载的独立 representation 视图。目标不存在、移出屏幕或开启“减弱动态效果”时回退到淡出。库负责动画，媒体、草稿及接受操作仍归应用所有。

### 权限弹窗或从设置返回

```swift
overlay.performExternalInteraction(
  from: self,
  interaction: .leavingApp,
  isValid: { [weak self] in self?.viewIfLoaded?.window != nil },
  operation: { _, complete in
    let url = URL(string: UIApplication.openSettingsURLString)!
    UIApplication.shared.open(url) { opened in
      Task { @MainActor in complete(opened) }
    }
  },
  resume: { [weak self] in self?.showMenu() }
)
```

权限弹窗或应用内系统选择器使用 `.inApp`，操作结束后在主 actor 调用 `complete(true)`。`.leavingApp` 还会等待原始 scene 重新激活。新的展示、owner 移除等情况会使旧回调失效。应用决定恢复哪个页面，并在 owner 移除时调用 `cancel()`。

### 添加底部悬浮按钮

页面实现 `OverlayPageChrome`，返回自己的前景控件层。`OverlayActionBar` 可以排列返回、添加以及可选的中间快门。将 `OverlayContentSafeArea` 的回调传给 `safeAreaClearance`，使用 `contentBottomInset` 给滚动内容预留空间。

将 `OverlayActionButton.actionStyle` 设为 `.emphasized`，即可使用 `accentColor` 强调已选中的操作。菜单尺寸、控件参数和生命周期协议见 [完整 API 文档](docs/API.zh-CN.md#控件与内容协议)。

## 键盘兼容性

库会尽量保留焦点，不需要先关闭键盘。`placementState` 会报告实际展示位置：覆盖键盘、位于键盘上方，或在应用窗口中。设置 `allowsKeyboardOverlap: false` 可关闭覆盖模式。

覆盖键盘依赖对 UIKit 未文档化类名 `UIRemoteKeyboardWindow` 的识别，相关逻辑集中在独立文件中，没有调用私有 selector，也不改变 key window。无法可靠识别宿主时，会回退到应用窗口并避让键盘。请提前初始化 controller，并在实际支持的设备、键盘和 scene 组合上验证；不能保证所有第三方键盘、浮动键盘和多显示器场景。

## 示例与开发

克隆仓库后打开 [Examples/OverlayDemo.xcodeproj](Examples/OverlayDemo.xcodeproj)，可体验 UIKit / SwiftUI 菜单、动态容器和固定图片的最近照片网格。示例会打开真实系统选择器，但不会读取真实照片库。

```sh
python3 scripts/verify.py
python3 scripts/verify.py --scenario pages --output .artifacts/pages-acceptance
npm run verify:distribution
```

模拟器验证需要 Xcode、iOS runtime、Python 3、AXe 和 ffmpeg/ffprobe，可按需设置 `DEVELOPER_DIR`。分发检查会从实际 npm 压缩包构建正常签名的 CocoaPods 与 SPM 宿主。另见 [验证记录](VALIDATION.md) 和 [发布说明](PUBLISHING.md)。

## 许可证

[MIT](LICENSE)。
