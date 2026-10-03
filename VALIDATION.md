# 本地验收记录

## 最新：可靠性修复 1–5

完成重复关闭回调合并与显式取消结果、present 成功后再提交页面状态、共享 SwiftUI 自然尺寸测量、同帧更新合并与静止布局跳过，以及按源窗口归属的键盘状态和保守屏幕匹配。新增 Reliability 示例与真实触摸驱动；接入文档的宿主清理统一使用 `cancel()`。

- iPhone 17 Pro / iOS 27 模拟器，正常自动签名构建通过。
- **12/12 组合通过**：Reliability 在聊天页 / Sheet × 浅色 / 深色四组合；最近照片、原菜单及系统选择器、动态容器、玻璃圆角各覆盖浅色聊天页与深色 Sheet。
- 生命周期场景验证重复关闭、强制完成、被新呈现替换、取消、控制器释放、无效锚点、回调重入、另一个源窗口及歧义键盘宿主回退。SwiftUI 页面通过真实点击验证异步增高、计数和返回状态保留、关闭后原草稿继续输入。
- 几何读取结果：系统参考圆角 62pt；12pt / 20pt 边距对应底角 50pt / 42pt；限宽及键盘上方回退仍为 24pt。
- 所有状态截图与 12 段录像抽帧已复核；本地必需证据覆盖 **12/12**。未声称逐帧播放或实测 CPU 降幅。静止时仍有 display-link 几何检查，跳过的是完整布局、测量和动画应用。
- 开发检查发现 iOS 27 键盘宿主提供不同 UIScreen 代理；仅在单物理屏幕时允许代理匹配，无法确认屏幕身份则回退。多屏幕、真实第三方键盘、iPad 浮动键盘、旧系统运行时仍未实机验收。
- 验收修正：返回按钮补齐圆角内边距与 44pt 点击区域；驱动等待首屏输入框和软件键盘就绪。早期录像占用、启动竞态及输入前重复空格的失败产物保留在 `.artifacts`，不计入通过结果。
- SPM 清单、podspec / Python 语法及 diff 检查通过。Lody / Ri Later 产品仓库没有改动。

[本轮本地报告](.acceptances/standalone-anchored-overlay/20261003-100955-reliability/report.md) · [结构化结果](.acceptances/standalone-anchored-overlay/20261003-100955-reliability/result.json)。包含真实触摸日志、AX/几何记录、截图、录像、构建日志及源码/二进制哈希。`lh` 未安装，未在线发布。

复验使用 `scripts/verify.py --scenario reliability`，其余场景分别指定 `pages` / `baseline` / `dynamic` / `glass` 与 `--host chat --appearance light` 或 `--host sheet --appearance dark`。本轮由外层 `lease(None, None)` 持有同一专用模拟器，子进程使用该租约 UDID；全部复用同一个最终签名构建。

## 上一轮：原生玻璃默认值

默认外观统一为无染色 Regular UIGlassEffect（iOS 26+）；旧系统回退 systemMaterial。固定尺寸 UIKit API、OverlayMenuButton、动态容器和页面 API 使用相同默认值。自绘内容可显式设置 `.transparent`，示例已移除重复背景。

iOS 27 模拟器三组针对性检查通过：深色 Sheet 的玻璃 / 圆角与实际效果类型、浅色聊天页的原菜单 / SwiftUI / 系统选择器回归、深色 Sheet 的最近照片导航与状态保留。正常签名构建和 diff 检查通过，截图及录像抽帧已复核。未单独运行 iOS 26 或旧系统；下方完整矩阵属于之前的构建。

[本轮本地报告](.acceptances/standalone-anchored-overlay/20261003-085556-native-glass-default/report.md)。命令使用 `scripts/verify.py` 的 `--scenario glass --host sheet --appearance dark`、`--scenario baseline --host chat --appearance light`、`--scenario pages --host sheet --appearance dark`，后两组复用首组构建。

## 上一轮：输入框 + 入口

最近照片网格已接入输入框 + → Recent Photos；Back 返回同一附件菜单，独立照片演示入口已移除。正常签名构建通过，照片导航四个组合（聊天页 / Sheet × 浅色 / 深色）通过，深色 Sheet 的系统文件 / 照片选择器、键盘回退、重复关闭和后台回归通过。截图与录像抽帧已复核。本次未修改库实现，动态 / 玻璃的完整矩阵结果见下方上一轮记录。

[本轮本地报告](.acceptances/standalone-anchored-overlay/20261003-084251-composer-photos/report.md)。运行命令：`scripts/verify.py --scenario pages --output .artifacts/plus-pages`；`scripts/verify.py --skip-build --scenario baseline --host sheet --appearance dark --output .artifacts/plus-baseline-sheet`。

## 上一轮：页面与动态容器

独立库已完成保留状态的页面转场、固定顶部向下展开与最近照片网格示例；本轮未修改 Lody 或 Ri Later 产品代码，变更尚未提交或发布。

- 环境：iPhone 17 Pro Simulator，iOS 27.0（24A5423a），Xcode 27 beta（27A5252f）。
- 结果：页面与照片网格 / 玻璃与圆角 / 动态容器 / 原有菜单 × 聊天页 / 原生 Sheet × 浅色 / 深色，**16/16 通过**。八个验收项的截图与视频本地覆盖 **8/8**。
- 几何实测：源窗口系统圆角 62pt；等距 12pt 时底角 50pt，等距 20pt 时底角 42pt。顶部保持 24pt。宽度上限 300pt 和键盘上方布局使用 24pt 回退底角。
- UIKit 和 SwiftUI 均验证 Regular/Clear 玻璃、低透明度蓝色 tint 与普通系统材质切换，计数状态不丢失；关闭按钮避开 Home Indicator，圆角外真实触摸关闭且不穿透输入。
- 补充检查：浅色聊天页无键盘时仍可保持顶部展开并滚动；已恢复 Lody Preview，停留在覆盖键盘的照片网格。
- 页面行为：内容淡入淡出与外壳、材质同步更新；菜单顶部保持，照片页覆盖键盘；选中照片、滚动偏移在返回和快速反转后保留；关闭后继续编辑原草稿。
- 动态行为：异步内容增高、展开/收回、快速反转、子视图计数与列表偏移保留、原草稿继续编辑。
- 原有行为：附件菜单键盘覆盖/回退、焦点保留、恰好一次的系统文件/照片选择器交接、重复开关和后台清理。
- 正常自动签名构建通过；SPM 清单、podspec 语法、Python 驱动语法和 diff 检查通过。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --scenario pages --output .artifacts/pages-final-pages
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --skip-build --scenario baseline --output .artifacts/pages-final-baseline
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --skip-build --scenario dynamic --output .artifacts/pages-final-dynamic
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --skip-build --scenario glass --output .artifacts/pages-final-glass
```

四组场景使用同一个最终构建。[本地结构化报告](.acceptances/standalone-anchored-overlay/20261003-064658-retained-pages/result.json) · [报告说明](.acceptances/standalone-anchored-overlay/20261003-064658-retained-pages/report.md)。归档包含 16 段录像、已审阅状态截图、真实触摸日志、AX/几何记录与源码 SHA-256。录像按首尾及过程抽帧复核，照片展开、返回和快速反转另做密集抽帧；未声称逐帧审阅全部录像。

Clear 玻璃、低透明度蓝色 tint 与普通系统材质切换，计数状态不丢失；关闭按钮避开 Home Indicator，圆角外真实触摸关闭且不穿透输入。
- 补充检查：浅色聊天页无键盘时仍可保持顶部展开并滚动；已恢复 Lody Preview，停留在覆盖键盘的照片网格。
- 页面行为：内容淡入淡出与外壳、材质同步更新；菜单顶部保持，照片页覆盖键盘；选中照片、滚动偏移在返回和快速反转后保留；关闭后继续编辑原草稿。
- 动态行为：异步内容增高、展开/收回、快速反转、子视图计数与列表偏移保留、原草稿继续编辑。
- 原有行为：附件菜单键盘覆盖/回退、焦点保留、恰好一次的系统文件/照片选择器交接、重复开关和后台清理。
- 正常自动签名构建通过；SPM 清单、podspec 语法、Python 驱动语法和 diff 检查通过。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --scenario glass --output .artifacts/glass-accepted
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --skip-build --scenario dynamic --output .artifacts/glass-dynamic-accepted
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --skip-build --scenario baseline --output .artifacts/glass-baseline-accepted
```

三组场景使用同一个最终库与示例构建。[本地结构化报告](.acceptances/standalone-anchored-overlay/20261002-235707-concentric-glass/result.json) · [报告说明](.acceptances/standalone-anchored-overlay/20261002-235707-concentric-glass/report.md)。归档包含 12 段录像、已审阅状态截图、真实触摸日志、AX/几何记录与源码 SHA-256。录像按首尾及过程抽帧复核，快速反转另做密集抽帧；未声称逐帧审阅全部录像。

Clear 玻璃会透出背后文字和按键，示例默认使用 Regular。尚未验证第三方键盘真机、iOS 16 运行时回退、iPad 浮动键盘、横屏、多场景或系统性 VoiceOver/Reduce Motion；也未进行实际使用方接入。旧系统回退分支以 iOS 16 部署目标编译通过，不能代替该版本运行验收。

新增 SwiftUI 页面工厂已编译；照片导航示例使用 UIKit 内容，原有 SwiftUI 单页路径已完成运行验证。

在线报告未上传：当前环境未安装 `lh`，本地完整证据已保留。
