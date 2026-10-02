# 本地验收记录

独立库已完成动态底部同心圆角与系统玻璃材质；本轮未修改 Lody 或 Ri Later 产品代码，变更尚未提交或发布。

- 环境：iPhone 17 Pro Simulator，iOS 27.0（24A5423a），Xcode 27 beta（27A5252f）。
- 结果：玻璃与圆角 / 动态容器 / 原有菜单 × 聊天页 / 原生 Sheet × 浅色 / 深色，**12/12 通过**。六个验收项的截图与视频本地覆盖 **6/6**。
- 几何实测：源窗口系统圆角 62pt；等距 12pt 时底角 50pt，等距 20pt 时底角 42pt。顶部保持 24pt。宽度上限 300pt 和键盘上方布局使用 24pt 回退底角。
- UIKit 和 SwiftUI 均验证 Regular/Clear 玻璃、低透明度蓝色 tint 与普通系统材质切换，计数状态不丢失；关闭按钮避开 Home Indicator，圆角外真实触摸关闭且不穿透输入。
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

在线报告未上传：`lh` 无认证，本地完整证据已保留。
