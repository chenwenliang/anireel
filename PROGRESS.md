# AniReel 进度日志

## 2026-10-28（启动日）
- 需求已由用户确认：iOS 原生、选风格后自动开摄像头、实时风格化、最长 30 秒、自动保存、中途终止也保存；第一版三风格（吉卜力系手绘治愈 / Q版 Chibi / 2.5D-3D NPR），风格可扩展。
- 项目名定为 AniReel（Sunny 定名）；任务书已落盘 `PROJECT_BRIEF.md`，含已定技术决策、分阶段计划与上线验收标准。
- 可行性已核查：AnimeGANv3 公开数据称 iPhone 14 上 512×512 推理可达约 50 FPS 且已有 CoreML 集成案例；NPR 走纯 Metal 着色器；管线采用 AVFoundation → StyleEngine → Metal 预览 + AVAssetWriter（与 Apple 官方 AVCamFilter 思路一致）。
- 环境限制（须知）：Sunny 本机为 Linux，无 Xcode/Swift，无法在本机编译 iOS 应用；本机产出完整 Xcode-ready 工程（XcodeGen），最终编译、真机测试与 TestFlight 需在 Mac 上完成。
- Claude Code 状态：v2.1.312，VCO 目录会话运行中；用量 Current session 35%、Current week 34%（2026-10-28 22:44 查），usage credits 保持关闭。
- 协作规则：Claude Code 中途决策由 Sunny 分析后判断（用户 2026-10-28 授权）；每日 09:00 (Asia/Tokyo) 进度汇报已设定（cron: anireel-daily-progress-9am）。
- 下一步：Phase 1 工程骨架（由 Claude Code 在 VCO 执行，Sunny 复核）。

## 2026-10-28 Phase 1 完成（工程骨架，待 Mac 编译验证）
- 产出：`project.yml`（XcodeGen；App + 单元测试 target；iOS 18（D1）；竖屏；Info.plist 由 XcodeGen 生成，含相机/麦克风/相册添加权限文案）、`AniReel/` 源码、`AniReelTests/`。
- 管线：`CameraSession`（后置广角，720p BGRA，`videoRotationAngle=90` 得到竖屏帧）→ `StyleEngine`（当前 StylePack 的 `StyleRenderer` 在 Metal 上把相机帧渲染进 720×1280 BGRA 池化 `CVPixelBuffer`，GPU 落后 2 帧即丢帧）→ `PreviewRenderer`（MTKView，aspect-fill 显示最新一帧）。Phase 2 的 `AVAssetWriter` 直接接 `StyleEngine` 输出的同一份 buffer，保证预览=成片。
- 风格扩展点：`StylePack`（descriptor + `makeRenderer`）、`StyleRenderer`（source/destination 纹理编码到 command buffer）、`StyleID` 为字符串结构体（新增风格不改枚举）、`StyleRegistry.shipping` 一行注册，重复 ID 启动即 precondition 失败。
- NPR 风格：`Styles/Packs/npr/`，单个 compute kernel：3×3 柔化 + 亮度分档（Posterize）+ 饱和度提升 + Sobel 墨线 + 程序化纸纹（无时间输入，输出确定）。
- 权限：`PermissionsManager` 统一相机/麦克风/相册添加三种状态与请求；相机被拒显示 `PermissionDeniedView`（去设置页）。Phase 1 只请求相机。
- 界面：选风格页（Registry 驱动卡片列表）→ 点选即进入相机页并自动开摄像头。中英双语 `Localizable.strings` / `InfoPlist.strings`。
- 决策记录：
  - Registry 目前只注册 npr；ghibli/chibi 在 Phase 3 实现后各加一行注册，避免选风格页出现不可用项。
  - 提前加入 `StyleRegistryTests`（查找、未知 ID、顺序），因为 Registry 属于 Phase 1。
  - App Icon/资源目录、录制、麦克风请求、中断处理均留给后续 Phase。
- 未验证（本机 Linux 无 Xcode）：未编译、未真机运行。Mac 上验证步骤：`brew install xcodegen && xcodegen generate && open AniReel.xcodeproj`，真机运行，选「2.5D 动画风」应立即看到描边+色块+纸纹的实时预览；`⌘U` 跑单元测试。需在 Signing 中设置 Team。
- D1/D2 应用于骨架（2026-10-28，见 `docs/DECISIONS.md`）：
  - Deployment Target 改为 iOS 18。
  - 新增 `Device/DeviceTier.swift`：按机型标识（iPhone12,x = A13 → 推理 384；iPhone13,x 及以后 = A14+ → 512；iPhone11,x 及更早 = 低于 A13 底线 → `nil` 不支持；非 iPhone/未知标识按新机处理不拦截）。模拟器读 `SIMULATOR_MODEL_IDENTIFIER`。`DeviceTierTests` 覆盖三档与未知标识。
  - 尚未接入：Phase 3 用 `DeviceTier.current?.inferenceSize` 作推理起始分辨率（热降档只往下调）；Phase 4 对 `nil` 显示「本机型不受支持」空状态。
  - D2：Mac 本地验证步骤改由 Codemagic 云端 Mac 执行（`codemagic.yaml` 于 Phase 4 落地）；project.yml 未写死 Team，签名保持 CI 可注入。
- 下一步：Phase 2 录制闭环。

## 2026-10-28 Phase 2 完成（录制闭环 + 前置摄像头，待云端编译验证）
- 录制状态机：`Recording/RecordingMachine.swift`。`RecordingPhase`（ready / recording(elapsed) / finishing / saving(url) / saved / tooShort / saveFailed(url) / recordingFailed）+ `RecordingMachine.reduce(phase, event) -> (phase, [effect])`，副作用（开始写、结束写、保存、删文件）由 `CameraModel` 执行。`DurationGuard`：30.0 秒硬上限（含等于）、1 秒最短。
- 写入：`Recording/ClipRecorder.swift`。`AVAssetWriter` MP4，H.264 720×1280@30fps（8 Mbps）+ AAC 单声道 44.1kHz。视频帧就是 `StyleEngine` 交给预览的同一份 buffer（预览=成片）。第一帧开启时间线；超过 30 秒的视频/音频帧丢弃，`endSession` 卡在 30.0 秒以内。
- 音频：麦克风授权后加入采集会话；拒绝、设备忙或静音时不建音轨，录无声视频，不阻塞。静音开关在录制开始时生效，录制中禁用。
- 保存：`Recording/PhotoLibrarySaver.swift`。仅添加权限（`.addOnly`），存入系统相册主库（D5 后，见下方修订）。失败时临时文件保留，弹窗提供 重试 / 丢弃（权限被拒时另有「打开设置」）。成功后删除临时文件，显示「已保存到相册」1.5 秒。
- 界面：录制按钮（进度环 30 秒满圈）、计时徽标（已录 / 剩余）、录制中隐藏返回键（禁止切风格）并禁用切换摄像头、镜像、静音。
- 前置摄像头（D3）：`CameraConfiguration`（position + mirrorsFront）。前后摄切换、前置镜像开关（默认开），镜像设在采集 connection 上，因此预览与成片像素一致。两颗摄像头都锁 30fps。
- 中断：采集会话 `wasInterrupted` / `runtimeError`、App 进入后台、离开相机页都会触发 stopRequested，按正常流程收尾并保存；录制到保存期间持有后台任务，保证切后台后能写完、存完。
- 测试：`RecordingMachineTests.swift`（DurationGuard 边界；用户停止、30 秒自动停、过短丢弃并提示重拍、保存失败保留文件并重试、丢弃删文件、写入失败、忙碌时忽略开始、空闲时忽略停止）。
- 决策记录（Sunny 可推翻）：
  - ~~相册权限改为读写（`.readWrite`）以支持 AniReel 专辑~~：已被 D5 推翻，见下方修订。
  - 采集会话自动接管音频会话，打开相机页会暂停用户正在播放的音乐。暂未改为混音；如需不打断音乐，Phase 4 改为手动配置 `AVAudioSession`。
- 首次在设备上运行时需要重点确认（本机无法验证）：前置摄像头 `videoRotationAngle=90` 加镜像后画面方向正确；麦克风采样率转 44.1kHz AAC 正常；来电中断时文件可正常收尾。
- 未编译、未运行（Linux 无 Xcode），按 D3 留待首次云端编译集中处理。
- 下一步：Phase 3 ML 风格（未开始）。

## 2026-10-28 Phase 2 修订（D5：相册权限退回仅添加）
- `PhotoLibrarySaver` 只做一次 `PHAssetCreationRequest`，存入系统相册主库；删除专辑查找/创建逻辑与有限权限分支（仅添加权限没有「有限」状态）。
- `PermissionKind.photoLibrary`（`.readWrite`）恢复为 `.photoLibraryAdd`（`.addOnly`）；相机页保存失败弹窗的「打开设置」判断随之更新。
- Info.plist 恢复 `NSPhotoLibraryAddUsageDescription`，删除 `NSPhotoLibraryUsageDescription`；中英 `InfoPlist.strings` 文案同步改为「保存到相册，不读取其他照片」。
- 保存失败保留临时文件 + 重试/丢弃的流程与 `RecordingMachine` 不变；现有测试不涉及相册，无需修改。
- 音频会话打断音乐：按 D5 留到 Phase 4 必改（预览时混音，录制开始才切录制会话）。
- 未编译、未运行。下一步：Phase 3（未开始）。
