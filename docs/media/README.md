# Recording the README demo / README 演示录制

The standalone **Showcase** screen uses the public library API and bundled photos.
It decodes photos before presentation, creates only visible collection cells, adds real thumbnails to its draft,
and animates the first accepted image into its destination. Panel-edge selection borders use `OverlayBoundaryHighlighting` from 0.3.0. It needs no account,
network access or Photos permission.

独立 **Showcase** 页面使用库的公开 API 和内置照片。展示前完成图片解码，网格只创建可见格子，选择后
将真实缩略图添加到草稿，并将第一张照片动画收进目标位置。贴边选中框使用 0.3.0 的 `OverlayBoundaryHighlighting`。无需账号、网络或照片权限。

The accepted capture was made on the 0.3.0 base with local changes subsequently
committed as `5976a05`; its library and example sources ship in 0.3.1. The recording
metadata preserves that capture provenance. The MP4 and GIF are unchanged.

已选定的录屏基于 0.3.0 和当时的本地修改，随后提交为 `5976a05`；对应库与示例源码
随 0.3.1 发布。录制元数据保留原始来源，MP4 和 GIF 内容未变。

## Capture / 录制

With Xcode, the iOS 26.4 runtime, Python 3, AXe 1.8+ and ffmpeg installed, run:

安装 Xcode、iOS 26.4 运行时、Python 3、AXe 1.8+ 和 ffmpeg 后运行：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  python3 scripts/record-showcase.py
```

Adjust `DEVELOPER_DIR` to your Xcode installation. `--runtime` selects another
installed runtime; `--output` changes the artifact directory.

将 `DEVELOPER_DIR` 改为本机 Xcode 的路径。`--runtime` 可选择其他已安装运行时，
`--output` 可修改产物目录。

The runner leases the dedicated verification Simulator, builds **Release** with
normal signing, prepares the keyboard and checks readiness before capture. It
records one continuous sequence: menu → photos → select two → add → keep typing.
After recording, it checks both attachments, continued physical keyboard input
and overlay cleanup, then shuts down its leased device. It saves `capture.mp4`,
`recording.json`, the interaction log and before/after screenshots. Native capture
uses HEVC; the published MP4 uses H.264 for browser compatibility.

脚本使用专用验证模拟器，以正常签名构建 **Release**，录制前准备键盘并检查就绪状态。
整个流程连续录制：菜单 → 照片 → 选择两张 → 添加 → 继续输入。录制后检查两张附件、
真实软件键盘输入和弹层清理，再关闭租用的模拟器。输出包含 `capture.mp4`、
`recording.json`、交互日志及录制前后的截图。原始录屏使用 HEVC，公开 MP4 使用
H.264 以兼容浏览器。

The example enables `CADisableMinimumFrameDurationOnPhone` in its generated
Info.plist. The controller requests higher display callback rates during motion
and restores system timing at rest. Actual rates remain system-controlled; see
[Apple's ProMotion guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays).

示例生成的 Info.plist 已启用 `CADisableMinimumFrameDurationOnPhone`。
controller 在动画期间请求较高的显示回调频率，静止后恢复系统节奏。实际帧率仍由系统决定，
参考 [Apple 的 ProMotion 指引](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)。

## Encode / 编码

Encode the entire capture at its original speed. These commands only change size,
compression and frame sampling; they do not trim, concatenate or retime the video.

完整保留录制时间线和原速。以下命令只调整尺寸、压缩和帧采样，不裁剪时间线、拼接或变速。

```sh
ffmpeg -i .artifacts/showcase/capture.mp4 \
  -vf 'scale=720:-2:flags=lanczos,fps=60' -fps_mode cfr \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
  -movflags +faststart -an docs/media/overlay-showcase.mp4

ffmpeg -i .artifacts/showcase/capture.mp4 \
  -filter_complex '[0:v]fps=50,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
  -loop 0 docs/media/overlay-showcase-preview.gif
```

Review the full video and sampled transition frames before updating either README.
Keep the MP4, GIF and recording metadata together. The READMEs use versioned GitHub
release asset URLs so their media also works on the npm page without adding video
files to the native npm package. Publish each replacement with a new filename
containing its content hash, then update both README links to avoid cached previews.

更新 README 前，检查完整视频和过渡抽样帧。MP4、GIF 和录制元数据一起保存。
README 使用按版本固定的 GitHub Release 资源地址，让 npm 页面也能显示媒体，
同时避免将视频文件打包进原生 npm 包。每次替换使用包含内容哈希的新资源文件名，
再同步两份 README 链接，避免读到缓存的旧预览。

## Earlier Lody recordings / 较早的 Lody 录屏

These recordings show [Lody iOS](https://github.com/Innei/lody-ios) integrating the
library at app commit `3b582f0`, on the iOS 26.4 Simulator with 1.5× playback.
The camera uses a deterministic fixture. The current README demo is the continuous
Showcase recording above.

以下录屏展示 Lody iOS 在应用提交 `3b582f0` 中接入本库的效果，使用 iOS 26.4 模拟器，
以 1.5 倍速播放；相机使用固定测试画面。当前 README 使用上面的 Showcase 连续录屏。

- [Photos: expand, select and add / 照片：展开、选择并添加](https://github.com/user-attachments/assets/e3288620-ad88-46c9-ae85-749ba4e518ba)
- [Camera: expand, retry and add / 相机：展开、重新拍摄并添加](https://github.com/user-attachments/assets/59b63b54-1145-40c7-9fe5-cc145b221bec)
