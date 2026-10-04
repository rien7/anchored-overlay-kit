# API 参考

[English](API.md) · [简体中文](API.zh-CN.md) · [返回 README](../README.zh-CN.md)

对应 **0.1.3** 的公开 API，尺寸单位均为 pt。`Required` 表示必须传入、没有默认参数。展示与 UIKit 操作应在主 actor 上执行。下面的 Swift 签名用于说明接口，不是可直接拼接运行的示例。

## Controller

在开始编辑之前创建 `AnchoredOverlayController()`，由使用方持续持有。

```swift
@discardableResult
func present(content: UIView, anchoredTo anchor: UIView, layout: OverlayLayout,
             appearance: OverlayAppearance = .standard,
             dismissLabel: String, allowsKeyboardOverlap: Bool = true)
  -> OverlayPresentationResult

@discardableResult
func present(content: UIView, anchoredTo anchor: UIView, preferredSize: CGSize,
             appearance: OverlayAppearance = .standard,
             dismissLabel: String, allowsKeyboardOverlap: Bool = true)
  -> OverlayPresentationResult
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `content` | Required | 内容视图；库提供外层容器。 |
| `anchoredTo` | Required | 活动源窗口中的可见锚点视图。 |
| `layout / preferredSize` | Required | 动态布局，或固定宽高。 |
| `appearance` | .standard | 容器圆角和背景。 |
| `dismissLabel` | Required | 关闭弹层的本地化无障碍标签。 |
| `allowsKeyboardOverlap` | true | 尝试覆盖键盘；false 保留在应用窗口中。 |
| `anchorTransition` | .none | `.none` 或 `.fade`；后者淡出原触发按钮，在清理时恢复原 alpha。 |
| `isPresented` | Read-only | 是否存在弹层，包括正在关闭的阶段。 |
| `resolvedFrame` | nil / read-only | 源窗口坐标中的目标矩形，不是动画中间帧。 |
| `placement` | nil / read-only | 实际 `OverlayPlacement`，展示期间读取。 |
| `placementState` | nil / read-only | 包含 placement 与可选 fallbackReason 的 `OverlayPlacementState`。 |
| `onLayout` | nil | `((CGRect) -> Void)?`；合并后的目标布局变化，不是逐帧动画回调。 |
| `onPlacementChange` | nil | `((OverlayPlacementState) -> Void)?`；实际宿主位置变化。 |
| `onDismiss` | nil | `(() -> Void)?`；整个弹层清理通知，不表示页面返回。 |

```swift
func updateLayout(_ layout: OverlayLayout, transition: OverlayTransition = .spring)
func updateAppearance(_ appearance: OverlayAppearance, transition: OverlayTransition = .spring)
func update(layout: OverlayLayout, appearance: OverlayAppearance,
            allowsKeyboardOverlap: Bool? = nil, transition: OverlayTransition = .spring)
func invalidateContentSize(transition: OverlayTransition = .spring)
```

layout / appearance 参数必须提供。更新不会重新挂载内容。`update` 同时更新几何和外观；其键盘策略为 `nil` 时保持原值。`.spring` 被打断时保留当前运动状态，`.immediate` 立即更新几何。UIKit 自然尺寸变化后调用 `invalidateContentSize`。“减弱动态效果”会立即更新几何，并保留淡入淡出。

### 关闭与取消

```swift
func dismiss(animated: Bool = true, completion: (() -> Void)? = nil)
func dismissWithResult(animated: Bool = true,
                       completion: @escaping (OverlayDismissalResult) -> Void)
func dismiss(to destination: UIView?, representation: UIView,
             cornerRadius: CGFloat = 8,
             destinationVisibility: OverlayDestinationVisibility = .unchanged,
             completion: @escaping (OverlayDismissalResult) -> Void)
func cancel()
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `animated` | true | 普通关闭是否使用动画；false 立即结束。 |
| `completion` | nil / Required | 普通 dismiss 可省略；带结果和目标视图的版本必须提供。清理后调用。 |
| `to` | Required (may be nil) | 同一 scene 中已挂载的目标；nil 或不在屏幕内时淡出。 |
| `representation` | Required | 未挂载、能在 bounds 内自行布局的视图。开始前先提交应用状态。 |
| `cornerRadius` | 8 | 目标缩略图圆角。 |
| `destinationVisibility` | .unchanged | `.unchanged` 或 `.hideDuringTransition`；目标 alpha 在回调前恢复。 |

重复关闭会合并到同一关闭过程，结果回调只调用一次。普通 completion 只在 `.dismissed` 和 `.notPresented` 时执行。新的展示会替代待执行的关闭操作。`cancel()` 立即移除弹层并取消待执行操作及外部恢复流程；owner 移除时调用它。长期持有的回调应弱引用 owner。

### 返回值与展示位置

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `OverlayPresentationResult` | — | `.presented` 开始展示；`.anchorUnavailable` 锚点不可用；`.inactiveScene` scene 非活动；`.superseded` 被重入的新操作替代；`.unavailable` 弹层不可用。 |
| `OverlayDismissalResult` | — | `.dismissed` 正常关闭；`.superseded` 被替代；`.cancelled` 被取消；`.notPresented` 原本没有弹层。 |
| `OverlayPlacement` | — | `.overKeyboard` 覆盖键盘；`.aboveKeyboard` 键盘上方；`.inAppWindow` 应用窗口。表示实际位置。 |
| `OverlayFallbackReason` | — | `.overlapDisabled` 主动关闭覆盖；`.keyboardHostUnavailable` 没有宿主；`.ambiguousKeyboardHost` 宿主不唯一；`.sourceNotEditing` 源窗口未编辑；`.unattributedKeyboard` 无法归属键盘；`.displayIdentityUnverified` 无法验证显示器身份。 |
| `OverlayPlacementState` | Read-only | `placement: OverlayPlacement` 与 `fallbackReason: OverlayFallbackReason?`。 |

### 外部交互

```swift
@discardableResult
func performExternalInteraction(
  from presenter: UIViewController,
  interaction: OverlayExternalInteraction = .inApp,
  isValid: @escaping () -> Bool,
  operation: @escaping (UIViewController, @escaping @MainActor (Bool) -> Void) -> Void,
  resume: @escaping () -> Void
) -> Bool
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `from` | Required | 原应用 presenter；已加载的 view 必须位于源窗口。 |
| `interaction` | .inApp | `.inApp` 用于权限或选择器；`.leavingApp` 还会等待离开应用后的原 scene 激活。 |
| `isValid` | Required | 检查原 owner 是否仍允许恢复，使用弱引用。 |
| `operation` | Required | 关闭后获得 presenter 与一次性的 complete(Bool)。结束时在主 actor 调用；false 表示外部应用打开失败，无需等返回激活。 |
| `resume` | Required | 操作结束且原 scene 可用时重建所需页面，弱引用 owner。 |

无法开始时返回 `false`（没有有效展示、正在关闭、已有外部操作，或 presenter 窗口不匹配）。调用会关闭并释放页面视图。`.leavingApp` 可跨后台恢复，`.inApp` 不可。新的 present / dismiss / cancel、owner 或窗口失效、scene 断开都会取消恢复。库不请求权限、不持有媒体业务。

## 布局与外观

```swift
OverlayLayout(width: Width, height: Height, position: Position = .anchored)
OverlayLayout.bottomEdge(inset: CGFloat = 12, height: Height, maxWidth: CGFloat = 600)
OverlayLayout.expandingToBottom(inset: CGFloat = 12, maxWidth: CGFloat = 600)
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `Width.fixed(CGFloat)` | Required value | 请求宽度，最终受可用空间约束。 |
| `Width.available(inset:max:)` | 12 / 600 | 可用宽度减去两侧间距，并限制最大宽度。 |
| `Height.fixed(CGFloat)` | Required value | 外层高度，包含库预留的底部安全距离。 |
| `Height.content(max:)` | Required cap | 先确定宽度再测量内容，限制总外层高度。 |
| `Height.viewportFraction(CGFloat)` | Required fraction | 源窗口高度的比例，受可用空间约束。 |
| `Position.anchored` | Default | 跟随触发按钮。 |
| `Position.bottom(inset:)` | 16 | 从已解析的安全区或键盘底边界向上留白。 |
| `Position.bottomEdge(inset:)` | 12 | 相对窗口底边定位。 |
| `Position.expandingToBottom(inset:)` | 12 | 记录上一目标矩形顶部，向窗口底部填充；忽略 height。首次展示使用安全区顶部。 |
| `bottomEdge(inset:height:maxWidth:)` | 12 / Required / 600 | 组合可用宽度与窗口左右、底部等间距。 |
| `expandingToBottom(inset:maxWidth:)` | 12 / 600 | 组合可用宽度与向底部展开的位置策略。 |
| `OverlayTransition` | .spring in updates | `.spring` 或 `.immediate`。 |

layout 的三个字段均可修改。先确定宽度再测量高度；实现 `OverlayContentSizing` 或 Auto Layout fitting，不要从上次分配的 frame 推导期望高度。滚动视图应使用有界高度或能提供自然高度的包装视图。贴边布局允许背景延伸到 Home Indicator 下方；库会从普通内容区域中扣除剩余安全距离，不要重复扣除。

```swift
OverlayAppearance(corners: Corners, background: Background = .glass(.regular))
OverlayAppearance(cornerRadius: CGFloat = 24, background: Background = .glass(.regular))
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `Corners.fixed(CGFloat)` | 24 via cornerRadius init | 统一圆角。 |
| `Corners.bottomConcentric(top:fallback:)` | 24 / 24 | 固定顶部圆角；iOS 26+ 满足条件时由系统解析底部圆角，否则使用 fallback。 |
| `Background.glass(_:tint:fallback:)` | Required style / nil / .systemMaterial | 样式为 `.regular` 或 `.clear`。iOS 26+ 使用 UIGlassEffect，旧系统使用指定 UIBlurEffect.Style。 |
| `Background.material(UIBlurEffect.Style)` | Required style | 系统模糊材质。 |
| `Background.color(UIColor)` | Required color | UIColor 背景。 |
| `Background.custom(@MainActor () -> UIView)` | Required factory | 非交互背景视图，由容器裁切。 |
| `corners / background` | Mutable | 修改配置后调用 updateAppearance 或 update。 |
| `cornerRadius` | 24 initially | 兼容属性：同心模式读取顶部圆角；写入会切换为统一固定圆角。 |
| `OverlayAppearance.standard` | Fixed 24 + regular glass | 默认外观；iOS 26 之前回退为 systemMaterial。 |
| `OverlayAppearance.transparent` | Fixed 0 + clear color | 内容需要自行提供完整外观时使用。 |

设备同心圆角要求左右、底部距窗口边缘相等，最大宽度限制未生效，并处于可用的底部贴边位置。稳定后基于源窗口解析 `max(0, 外圆角 − 间距)`。宽度受限、边距不等、锚点或键盘上方布局及旧系统使用 fallback，顶部保持固定。较小容器会限制圆角，过渡中进行插值。同一内置背景保留效果视图，改变背景时可交叉淡入淡出。玻璃是容器的非交互背景，不会给每行叠加一层。

## 保留状态的页面

```swift
OverlayPages(controller: AnchoredOverlayController)
OverlayPage(id: String, layout: OverlayLayout,
            appearance: OverlayAppearance = .standard,
            contentLayout: OverlayPageContentLayout = .stable,
            content: @escaping () -> UIView)
OverlayPage.swiftUI(id: String, layout: OverlayLayout,
                    appearance: OverlayAppearance = .standard,
                    @ViewBuilder content: @escaping () -> Content)

@discardableResult
func present(_ page: OverlayPage, anchoredTo anchor: UIView,
             dismissLabel: String, allowsKeyboardOverlap: Bool = true)
  -> OverlayPresentationResult
func push(_ page: OverlayPage, transition: OverlayTransition = .spring)
func back(transition: OverlayTransition = .spring)
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `controller` | Required | 由 owner 持有 controller 和 OverlayPages；在 OverlayPages 中为公开只读属性。 |
| `id` | Required | 稳定的逻辑页面 ID，只读；关闭前相同 ID 复用已缓存视图。 |
| `layout` | Required | 页面布局，OverlayPage 中可修改。 |
| `appearance` | .standard | 页面容器外观，可修改。 |
| `contentLayout` | .stable | `.stable` 按目标尺寸布局；`.viewport` 跟随动画中的尺寸。可修改；swiftUI 工厂初始为 .stable。 |
| `content / makeContent` | Required | 每个保留 ID 只构造一次。存储为可修改的 makeContent；业务状态由应用持有。 |
| `anchoredTo / dismissLabel` | Required | 与 controller.present 含义一致。 |
| `allowsKeyboardOverlap` | true | 展示时的键盘覆盖策略。 |
| `transition` | .spring | push / back 的过渡：`.spring` 或 `.immediate`。 |
| `pageID` | nil / read-only | 当前页面 ID。 |
| `canGoBack` | Read-only | 是否有可返回的上一页。 |

内部导航使用 push / back，不要重新 present。重新展示会开始新的页面缓存生命周期。push 当前 ID 或在根页面 back 不执行操作。非活动页面不接收触摸和无障碍焦点。关闭时释放缓存视图，应用模型可继续持有。页面内容不缩放；容器几何、裁切和内容显隐使用同一动画时钟。SwiftUI 模型可原位更新，替换工厂不会重建已经缓存的 ID。

## SwiftUI 触发按钮

```swift
OverlayButton(controller: AnchoredOverlayController, layout: OverlayLayout,
              appearance: OverlayAppearance = .standard,
              accessibilityLabel: String, dismissLabel: String,
              allowsKeyboardOverlap: Bool = true,
              @ViewBuilder label: () -> Label,
              @ViewBuilder content: () -> Content)

OverlayMenuButton(controller: AnchoredOverlayController,
                  systemImage: String = "plus", label: String,
                  dismissLabel: String, preferredSize: CGSize,
                  appearance: OverlayAppearance = .standard,
                  allowsKeyboardOverlap: Bool = true,
                  @ViewBuilder content: @escaping () -> Content)
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `controller` | Required | 与此按钮共用、身份稳定的 controller。 |
| `layout / preferredSize` | Required | OverlayButton 使用动态 layout；OverlayMenuButton 使用固定尺寸。 |
| `appearance` | .standard | 外层容器外观，避免在内容中重复添加背景。 |
| `accessibilityLabel / label` | Required | 本地化触发按钮标签；OverlayButton 另接收 label 视图构造闭包。 |
| `systemImage` | "plus" | OverlayMenuButton 的 SF Symbol 名称。 |
| `dismissLabel` | Required | 本地化关闭无障碍标签。 |
| `allowsKeyboardOverlap` | true | 尝试覆盖键盘。 |
| `label closure` | Required on OverlayButton | 自定义 SwiftUI 触发按钮外观。 |
| `content closure` | Required | SwiftUI 页面内容。 |

`OverlayButton` 在父状态变化时更新同一内容树，自动使自然高度测量失效，遵守 `.disabled`，移除时仅取消自己持有的展示。保持 identity 稳定，改变 `.id` 会重置状态。UIViewRepresentable 生命周期方法与 Coordinator 是 SwiftUI 桥接实现，不是额外配置项。OverlayMenuButton 是其便捷封装。

## 控件与内容协议

```swift
OverlayControlMetrics()
OverlayMenuContent(items: [OverlayMenuContent.Item],
                   metrics: OverlayControlMetrics = .init(),
                   accentColor: UIColor = .systemBlue)
OverlayMenuContent.Item(title: String, systemImage: String,
                       accessibilityIdentifier: String? = nil,
                       isSelected: Bool = false, isEnabled: Bool = true,
                       action: @escaping () -> Void)
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `diameter` | 40 | 按钮视觉尺寸与菜单图标圆盘直径。 |
| `hitSize` | 44 | 操作按钮最小点击区域；父视图需留出空间。 |
| `symbolSize` | 16 | SF Symbol 字号，medium 字重和 scale。 |
| `symbolBox` | 20 | 菜单图标布局容器尺寸。 |
| `menuRadius` | 40 | 计算菜单内部间距的外圆角；也要设置到 appearance。 |
| `rowHeight` | 56 | 菜单行最小高度。 |
| `labelGap` | 12 | 图标、文字和尾部勾选区域之间的间距。 |
| `menuSideInset` | Derived / read-only | `max(0, menuRadius - diameter / 2)`，默认 20。 |
| `menuVerticalInset` | Derived / read-only | `max(0, menuRadius - rowHeight / 2)`，默认 12。 |
| `symbolConfiguration` | Derived / read-only | 由 symbolSize、medium 字重及 scale 得出的 UIImage.SymbolConfiguration。 |
| `items` | Required | 按顺序排列的菜单操作。 |
| `metrics` | .init() | 统一视觉尺寸。先用 var 修改字段，再传入。 |
| `accentColor` | .systemBlue | 选中行文字、图标和勾选标记颜色。 |
| `Item.title / systemImage` | Required | 本地化行标题及 SF Symbol 名称，只读。 |
| `Item.accessibilityIdentifier` | nil | 可选的 UI 自动化标识。 |
| `Item.isSelected` | false | 显示强调色、勾选及无障碍选中状态。 |
| `Item.isEnabled` | true | 启用行交互。 |
| `Item.action` | Required | 点击时执行；关闭或导航由调用方决定。 |

metrics 是构造控件时传入的值。Item 状态在创建 `OverlayMenuContent` 时读取，不是实时绑定，也没有公开的原位菜单更新接口。行状态需动态变化时应构造替换内容，或提供自己的响应式内容。

```swift
OverlayActionButton(metrics: OverlayControlMetrics = .init())
OverlayActionBar(leading: UIView, trailing: UIView, center: UIView? = nil,
                 centerSize: CGSize = CGSize(width: 74, height: 74),
                 metrics: OverlayControlMetrics = .init(), sideInset: CGFloat = 12,
                 rowHeight: CGFloat = 44, bottomMargin: CGFloat = 12,
                 contentSpacing: CGFloat = 12)
```

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `OverlayActionButton.metrics` | .init() / read-only | 初始化时确定的控件尺寸。 |
| `actionStyle` | .neutral | `.neutral` 或 `.emphasized`；iOS 26+ 为系统玻璃，旧系统为 filled 配置。 |
| `accentColor` | .systemBlue | 强调操作的背景色。 |
| `horizontalPadding` | 0 | 内容水平内边距。 |
| `leading / trailing` | Required | 左侧固定直径控件、右侧由内容决定宽度的控件。 |
| `center` | nil | 可选的中间自定义控件。 |
| `centerSize` | 74 × 74 | 中间控件的固定尺寸。 |
| `metrics` | .init() | 两侧控件的视觉直径与点击区域。 |
| `sideInset` | 12 | 基础左右间距，再加上传入的左右安全距离。 |
| `rowHeight` | 44 | 最终只读高度为请求值、metrics.hitSize 和存在的中间控件高度的最大值。 |
| `bottomMargin` | 12 | 最小底部间距，初始化后只读。 |
| `contentSpacing` | 12 | 计算 contentBottomInset 时控件上方的间距，只读。 |
| `safeAreaClearance` | .zero | 由页面安全区回调更新的 UIEdgeInsets。 |
| `controlsGuide` | Read-only | 用于定位应用额外控件的 UILayoutGuide。 |
| `contentBottomInset` | Derived / read-only | `max(bottomMargin, safeAreaClearance.bottom) + rowHeight + contentSpacing`。 |

通过标准 UIButton configuration 设置标题、图片与加载状态，通过 UIKit API 设置动作。样式变化会保留标题、图片与加载指示器；按钮前景色为白色。OverlayActionBar 是覆盖整个可见区域的控件层，其两侧包装视图会预留最小点击区域。单独使用按钮时需自行预留该区域。

| 参数 / 成员 | 默认值 | 含义 |
| --- | --- | --- |
| `OverlayContentSizing` | Optional protocol | `overlayHeight(forWidth: CGFloat) -> CGFloat` 覆盖 UIKit 自然高度测量。 |
| `OverlayContentSafeArea` | Optional protocol | `overlayExtendsToEdges: Bool` 默认 true；`overlaySafeAreaInsetsDidChange(_ insets: UIEdgeInsets)` 接收容器局部的额外安全距离。 |
| `OverlayPageChrome` | Optional protocol | `overlayChrome: UIView` 提供持有的前景层；按实时可见尺寸布局，空白区域将触摸传递给内容。 |
| `OverlayPageActivity` | Optional protocol | `overlayPageActivityDidChange(isActive: Bool)` 在页面激活或停用时启动、停止应用资源。 |

默认内容获得扣除安全距离后的区域。采用 `OverlayContentSafeArea` 后，图像可铺满容器，控件遵守传入的额外安全距离（目前主要是底部 Home Indicator）。overlayExtendsToEdges 返回 false 可退回普通模式。几何变化时可能持续回调，不要递归修改弹层布局。OverlayPages 会给过渡中仍可见的视图传递当前安全距离；资源是否活动则独立由 OverlayPageActivity 控制。即使视图仍被缓存，停用时也应停止相机、播放和订阅。
