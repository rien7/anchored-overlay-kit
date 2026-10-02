# 本地验收记录

独立库完成验收，未修改 Lody 或 Ri Later 的产品代码。库与示例尚未对外发布。

- 环境：iPhone 17 Pro Simulator，iOS 27.0（24A5423a），Xcode 27 beta（27A5252f）。
- 结果：聊天页 / 原生 Sheet × 浅色 / 深色，**4/4 通过**；两个验收项的截图与视频本地覆盖 **2/2**。
- 行为：键盘覆盖区域真实触摸、无穿透、关闭后插入点与草稿保留、键盘上方回退、SwiftUI 触发器与内容、动作清理后仅执行一次、系统文件与照片选择器返回、重复开关、后台和 Sheet 退出清理。
- 校验：正常自动签名构建通过，SPM 清单与 CocoaPods podspec 解析通过。截图、录像抽帧及首中尾帧已目视复核。

复现命令：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/verify.py --output .artifacts/acceptance-final
```

[结构化本地报告](.acceptances/standalone-anchored-overlay/20261002-132234-final/result.json) · [报告说明](.acceptances/standalone-anchored-overlay/20261002-132234-final/report.md)。完整原始捕获位于 `.artifacts/acceptance-final`，归档包含 4 段录像、已审阅截图、触摸日志、最终 AX 状态与源码 SHA-256。

示例关闭自动纠错、拼写检查和自动大小写以稳定测试；库不修改使用方输入配置。Recent Photos 仅验证业务回调，Files 和 Photo Library 打开真实系统选择器。第三方键盘真机、iPad 浮动键盘、横屏、多场景以及最低支持版本 iOS 16 尚未验收。覆盖能力依赖可用的系统键盘窗口，不能保证所有第三方键盘。

在线报告未上传：`lh` 返回无认证，已保留可供后续 ingest 的本地报告。
