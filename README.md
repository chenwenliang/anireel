# AniReel — 实时风格相机（iOS 原生）

打开即是作品流（没有作品时展示三种风格的示例）→ 点底部中央拍摄键 → 抖音式拍摄页，快门上方切换风格，实景实时变成所选风格（最长 30 秒）→ 自动保存到相册并加入「我的作品」；中途终止也保存。所见即所得：预览与成片是同一份风格化画面。

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
- 界面（D9 / Phase 7）：底部导航「作品 | 风格 | 中央拍摄键 | 示例 | 我的」，统一设计令牌（`AniReel/DesignSystem`：极光蓝紫渐变、双色 A 标记渐变、珊瑚色唯一暖色点缀、浅色界面）；拍摄页为抖音式布局（右侧工具栏、快门上方风格页签、左下风格面板、右下最新作品）；游客额度用完时注册墙以半屏弹层出现在拍摄页上。
- 功能补齐（D7 / Phase 6）：首次启动引导、保存后结果页（循环回放 / 分享 / 重拍）、「我的作品」本地库、设置页（账户与删除账户、拍摄默认值、存储、隐私政策 / 用户协议、反馈）、3 秒定时、后置手电筒、网格线、长按看原图。
- 账户（D6）：启动不强制登录；游客可免费成功保存一条视频，之后需注册/登录（本机账户，Keychain 存加盐哈希，无网络）。详见 `docs/ACCOUNTS.md`。

## 目录

```
project.yml                 XcodeGen 工程源（*.xcodeproj 不入库）
AniReel/App                 App 入口、根视图（底部导航外壳、中央拍摄键、不支持机型页面）
AniReel/DesignSystem        设计令牌（Theme）与共用组件（A 标记、渐变按钮、胶囊标签、空状态/错误状态）
AniReel/Home                主界面纯逻辑：作品流内容选择（HomeFeed / SampleWork）、风格默认值（StyleChoice）、额度状态、导航状态（ShellState）
AniReel/Accounts            AuthService 协议、LocalAuthService、RecordingGate、Keychain 存储、AccountStore
AniReel/Capture             帧源：CameraSession（真机）、DemoFrameSource（模拟器）、音频会话策略
AniReel/Rendering           MetalContext、StyleEngine、KernelRenderer、预览
AniReel/ML                  CoreMLStyleRenderer、InferenceGovernor（只降不升）
AniReel/Styles              StylePack 协议、StyleRegistry、Packs/{ghibli,chibi,npr}
AniReel/Recording           录制状态机、ClipRecorder（AVAssetWriter）、相册保存
AniReel/Features            作品流（Home）、风格页与示例页（Styles）、我的（Profile）、相机页、账户、结果页、我的作品、设置与法律页面、首次启动引导
AniReel/Library             我的作品本地库（ClipLibraryIndex 元数据 + 视频副本）
AniReel/Storage             JSON 文件存储（偏好设置等；不用 UserDefaults）
AniReel/Device              DeviceTier（A13=384，A14+=512）
AniReel/Resources           Info.plist 文案、Assets.xcassets、PrivacyInfo.xcprivacy、隐私政策 / 用户协议（en、zh-Hans）、模型目录
AniReelTests                纯逻辑单元测试
scripts/                    模型转换、图标 / 启动标记 / 品牌标记 / 示例作品封面生成
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
- `docs/ACCOUNTS.md`：账户设计、存储与安全、正式后端上线清单
