# AniReel — 实时风格相机（iOS 原生）

选风格 → 摄像头自动开启 → 实景实时变成所选风格拍摄（最长 30 秒）→ 自动保存到相册；中途终止也保存。所见即所得：预览与成片是同一份风格化画面。

## 风格

| 风格 | 实现 | 不带模型时 |
| --- | --- | --- |
| 手绘治愈风 Hand-Painted Anime | Core ML（AnimeGANv3 Hayao 槽位）+ 重采样 | Metal 近似（柔化、平滑色阶、暖色、柔和描边） |
| Q 版萌系 Chibi Pop | Core ML 槽位 + Metal 后处理 | Metal 后处理直接作用于相机帧 |
| 2.5D 动画风 NPR Anime | 纯 Metal 着色器 | — |

新增风格：在 `AniReel/Styles/Packs/<id>/` 实现 `StylePack`，在 `StyleRegistry.shipping` 注册一行，拍摄管线无需改动。

## 平台与约束

- iOS 18+，iPhone 11 / SE（第 2 代）及以后（A13 起）；低于 A13 显示「不受支持」页面。
- Swift + SwiftUI + AVFoundation + Metal + Core ML，纯端上处理，不联网、不收集数据、不追踪。
- 相册只申请「仅添加」权限；麦克风可选，拒绝或静音时录无声视频。
- 预览时不打断用户正在播放的音乐，只有带声音录制时才切换为录音会话。

## 目录

```
project.yml                 XcodeGen 工程源（*.xcodeproj 不入库）
AniReel/App                 App 入口、根视图（含不支持机型页面）
AniReel/Capture             帧源：CameraSession（真机）、DemoFrameSource（模拟器）、音频会话策略
AniReel/Rendering           MetalContext、StyleEngine、KernelRenderer、预览
AniReel/ML                  CoreMLStyleRenderer、InferenceGovernor（只降不升）
AniReel/Styles              StylePack 协议、StyleRegistry、Packs/{ghibli,chibi,npr}
AniReel/Recording           录制状态机、ClipRecorder（AVAssetWriter）、相册保存
AniReel/Features            风格选择页、相机页
AniReel/Device              DeviceTier（A13=384，A14+=512）
AniReel/Resources           Info.plist 文案、Assets.xcassets、PrivacyInfo.xcprivacy、模型目录
AniReelTests                纯逻辑单元测试
scripts/                    模型转换、占位图生成
docs/                       DECISIONS、MODELS、APPSTORE
```

## 构建

- 本机（Linux）不编译。云端：Codemagic 工作流 `ios-simulator-dev`（`codemagic.yaml`）执行 `xcodegen generate`、未签名模拟器构建与单元测试。
- 有 Mac 时：`brew install xcodegen && xcodegen generate && open AniReel.xcodeproj`。
- 签名、TestFlight、发布工作流按 D2/D4 暂缓。

## 模拟器演示模式

模拟器没有相机。在模拟器或无相机设备上，App 自动改用 `DemoFrameSource`：生成 30 fps 的动态画面（后摄：风景；前摄：笑脸），送入与真机相同的 StyleEngine → 预览 + 录制 → 相册保存流程，左上角显示「演示画面」标记。演示模式不录声音。真实帧率、相机效果、发热降档只能在真机上验证。

## 模型

模型文件不入库。来源、许可（AnimeGANv3 仅限非商业用途，商用需作者授权）与转换步骤见 `docs/MODELS.md`；转换脚本 `scripts/convert_animegan.py`。App 在不带模型时完整可用。

## 文档

- `PROJECT_BRIEF.md`：任务书
- `PROGRESS.md`：进度日志
- `docs/DECISIONS.md`：决策记录
- `docs/MODELS.md`：模型来源与许可
- `docs/APPSTORE.md`：商店文案草稿与提交清单
