# 视频播放器（VideoPlayer）

一个轻量的原生 macOS 视频播放器，专为 Apple Silicon（M 系列芯片）优化。

**双解码后端，真正通吃所有格式：**

- 🎬 **AVFoundation 硬件解码**（默认）——省电、流畅，覆盖 MP4 / MOV / MKV / WebM 等常见格式
- 🧩 **FFmpeg 软解兜底**——当 AVFoundation 无法解码时**自动切换**，也可手动切换（⌥⌘R），通吃 DivX/Xvid AVI、FLV、WMV、FFV1、DTS 音轨等一切冷门格式

## 功能

- 🎬 播放几乎所有视频/音频格式（FFmpeg 兜底，无格式死角）；**FFmpeg 支持 VideoToolbox 硬解**（GPU 解码，4K 更流畅省电）
- 🎛️ 统一自绘控制条：上一个/下一个、播放/暂停、**倍速按钮（点击弹出菜单）**、进度拖动（**带章节刻度**）、时间、音量、**音频输出路由（隔空播放）**、全屏；**播放时自动隐藏，动鼠标唤出**
- 📥 拖拽文件到窗口即可播放；⌘O 打开文件（可多选，自动连播）；⌥⌘O 打开文件夹（**自然排序**，第2集在第10集前）；**⌘U 打开流媒体 URL（HLS / RTSP / RTMP）**
- 📋 **播放列表侧栏**（⌘⇧L）：双击切换、Delete 移除、**拖拽排序**、拖文件进列表追加，多文件时自动展开
- 💬 字幕：外挂 `.srt`/`.vtt` 自动加载；**MKV 内嵌字幕轨提取与选择**（右键 → 字幕，**按文件记忆选择**）；字幕字号/颜色/位置可调；**字幕同步微调（G/H，±0.5s）**；自动剥离 VTT/SRT 的 HTML 标签
- 🔊 **多音轨切换**（右键 → 音轨，双语 MKV 中英切换，**按文件记忆**）；软解模式支持**音频延迟微调**（A/V 同步）
- 🔁 **A-B 循环**（A/B 键设点，学外语/扒片神器）；循环播放；**倍速跨启动记忆**（0.25x–4x）
- 📖 **章节**：MKV/MP4 章节刻度显示在进度条上，右键 → 章节 直接跳转
- 🖼️ **画中画**（macOS 12+，硬解模式）
- 🖥️ **迷你模式**（⌘M）：无边框置顶小窗，双击画面或 Esc 退出
- 🎵 **媒体键与控制中心 Now Playing**：Mac 键盘 F7/F8/F9 播放键可控制播放
- 📸 **⌘S 截图**：当前画面存为 PNG
- ℹ️ **⌘I 媒体信息**：容器/编码/分辨率/码率/音轨一览
- 🖱️ **右键菜单**：打开/文件夹/URL/字幕轨/音轨/章节/播放控制/速度/A-B 循环/循环/置顶/播放列表/软解切换/截图/媒体信息/画中画/迷你模式/全屏/偏好设置
- ⚙️ **偏好设置窗口**（⌘,）：解码后端、循环、自动播放、FFmpeg 硬解开关、字幕样式/位置/**同步偏移**、窗口置顶/全屏/适配视频大小，全部持久化保存
- ⏯️ **记忆播放位置**：关闭后下次打开自动续播；文件菜单有**最近播放**记录（**显示上次进度**）；窗口位置/大小自动记忆
- 🔄 **旋转视频自动转正**（手机竖拍等带 display matrix 的文件，软解模式自动旋转像素并适配窗口）
- 🪟 打开视频后窗口自动适配视频尺寸（可在设置中关闭）
- ⌨️ 快捷键：`空格`/`K` 播放/暂停 · `←→` 快退/快进 5 秒（⇧=10 秒）· `J/L` 快退/快进 10 秒 · `↑↓` 音量 · `G/H` 字幕同步 · `A/B` A-B 循环 · `Esc` 退出迷你模式 · `⌘←/⌘→` 上一个/下一个 · `⌘S` 截图 · `⌘U` 打开 URL · `⌘I` 媒体信息 · `⌘M` 迷你模式 · `⌃⌘F` 全屏 · `⌥⌘R` 软解 · `⌘,` 偏好设置 · `⌘⇧L` 播放列表
- 🗂️ 已在 Info.plist 中声明常见格式，可通过「打开方式」用本应用打开

## 依赖

**零外部依赖**。FFmpeg 及其全部动态库已内嵌进 app 的 `Contents/Frameworks/`（通过 `@rpath` 加载），
可直接分发到任何 Apple Silicon Mac 使用，无需对方安装 FFmpeg。

## 构建

```bash
./build.sh          # 编译 + 内嵌 FFmpeg + 签名 → build/VideoPlayer.app
./make_dmg.sh       # 打包成安装镜像 → VideoPlayer-1.0.6.dmg
```

产物在 `build/VideoPlayer.app`。

## 运行

```bash
open build/VideoPlayer.app
```

也可直接拖入 `/Applications` 使用，或在终端直接打开文件：

```bash
open -a VideoPlayer 某部电影.mkv
```

## 设为默认播放器（可选）

将 app 拖入 `/Applications` 后，在任意视频文件上 `右键 → 显示简介 → 打开方式 → 选择「视频播放器」→ 全部更改`。

## 分发

- 直接分享 `build/VideoPlayer.app`（自包含），或
- 分享 `VideoPlayer-1.0.6.dmg`（17M），对方双击挂载后拖入 Applications 即可

> 提示：本应用为本地构建 + ad-hoc 签名，首次在别的 Mac 打开若被 Gatekeeper 拦截，
> 可右键点击 → 「打开」，或执行 `xattr -dr com.apple.quarantine VideoPlayer.app`。

### 正式发布（Developer ID 签名 + 公证，无 Gatekeeper 拦截）

```bash
./release.sh        # 签名 → 公证 → 装订 → 公证 DMG，一条命令产出可分发安装包
```

一次性准备（详见 `release.sh` 头部注释）：

1. 在 developer.apple.com 创建并安装 **Developer ID Application** 证书
2. 存储公证凭据：`xcrun notarytool store-credentials VideoPlayerNotary --apple-id ... --team-id ... --password ...`
   （或用 App Store Connect API 密钥，推荐）

未配置证书时 `./build.sh` 自动退回 ad-hoc 签名，不影响本机开发调试。

## 技术说明

- **AVKit 后端**：`AVPlayer` + 自建 `AVPlayerLayer` 视图（同时为画中画提供 `playerLayer` 源），硬件解码
- **FFmpeg 后端**：`libavformat`/`libavcodec` 解复用 + 软解/VideoToolbox 硬解 → `swscale`/`swresample` 转码 → `AVSampleBufferRenderSynchronizer` 音视频同步渲染（`AVSampleBufferDisplayLayer` 视频 + `AVSampleBufferAudioRenderer` 音频）
- **色彩管理**：swscale 按源色彩空间（BT.601/709/2020）与量程（limited/full）转换到 sRGB；HDR（PQ/HLG）内容做对比度/饱和度软补偿
- **旋转**：读取帧级 display matrix（`av_display_rotation_get`），90/180/270 时用 vImage 旋转像素并适配窗口
- **性能**：BGRA 像素缓冲走 `CVPixelBufferPool` 复用；解码/渲染 5 秒缓冲背压
- **内嵌字幕**：小文件（<1.5GB）播放前一次性 demux 提取；大文件/网络流由**独立线程**用自己的 demux 上下文后台提取，不阻塞首帧
- **线程安全**：播放线程与主线程的共享状态（seek 请求、暂停/停止、倍速、音轨切换、字幕字典、截图帧）全部经锁保护
- **音轨切换**：软解模式在播放线程内重建解码器 + 重采样器，从当前播放位置无缝续播
- 切换策略：默认 AVKit；`AVPlayerItem.status == .failed` 时自动回退 FFmpeg（实测切换延迟约 3ms）

## 已知限制

- **HDR**：软解模式将 HDR 转换为 8-bit SDR 时只做近似补偿，非完整 tone mapping（完整映射需引入 libplacebo/zscale）
- **ASS 特效字幕**：内嵌 ASS 以纯文本渲染（样式/定位/动画丢弃）；完整特效需集成 libass（新依赖链）
- **隔行扫描**：软解模式未做去交错（需 avfilter/yadif）
- **画中画**：仅硬解模式（macOS PiP 只支持 `AVPlayerLayer` 源），需 macOS 12+
- **音轨切换（硬解模式）**：依赖 AVFoundation 的 media selection，对个别封装可能选项不全；软解模式任意切换

## 项目结构

```
VideoPlayer/
├── main.swift             # 应用主程序（UI、AVKit 后端、播放列表、右键菜单、截图/画中画/迷你模式等）
├── FFmpegPlayer.swift     # FFmpeg 软解播放器后端（内嵌字幕提取、音轨切换、旋转、色彩管理、章节）
├── Settings.swift         # 设置存储 + 偏好设置窗口 + 最近记录/续播/轨道偏好记忆
├── ControlBar.swift       # 软解模式自绘控制条（章节刻度、倍速按钮、音频输出路由）
├── Subtitle.swift         # 字幕模型与解析（SRT/VTT/ASS）
├── bridge.h               # Swift ↔ FFmpeg C 桥接头
├── Info.plist             # 应用元数据与文件类型关联
├── build.sh               # 一键编译打包 + 签名 + 内嵌 FFmpeg dylib
├── bundle_dylibs.py       # FFmpeg 动态库收集与 @rpath 改造
├── make_dmg.sh            # DMG 安装镜像打包
├── generate_icon.swift    # 图标生成脚本
├── AppIcon.icns           # 应用图标
├── test_*.swift           # 开发用验证工具
└── build/VideoPlayer.app
```
