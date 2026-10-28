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

## 2026-10-28 Phase 3 完成（ML 风格，待云端编译验证）
- 共享 ML 运行时：`ML/CoreMLStyleRenderer.swift`。相机帧 → Metal 重采样到推理尺寸 → Core ML（`computeUnits = .all`，输出写入自有 IOSurface 缓冲区）→ 风格的 finish pass 输出 720×1280。在视频队列上同步推理，迟到帧由采集端丢弃；任何 ML 失败（加载/推理）改用该风格的 Metal 回退。模型在首帧及每次降档后按需加载。
- 降档：`ML/InferenceGovernor.swift`（纯逻辑）。阶梯 512 → 384 → 256；起始 = `DeviceTier.current`（A13 384，A14+ 512；低于底线按 A13 处理，Phase 4 再拦截）与已打包模型的交集；每 30 帧窗口内过半帧超 1/30 秒或热状态 serious/critical 时降一档，**只降不升**。推理帧为与 S×S 同像素量的竖屏尺寸（512 → 384×680，384 → 288×512，256 → 192×344）。
- 风格包：
  - `Styles/Packs/ghibli`：槽位 `animegan_hayao_<S>`，finish 为纯重采样；缺模型时 `ghibliApprox`（柔化 + 平滑色阶 + 暖色提亮 + 柔和描边）。
  - `Styles/Packs/chibi`：槽位 `animegan_chibi_<S>`，finish 为 `chibiPost`（高饱和 + 粗描边 + 双环模糊得到圆润色块）；缺模型时同一 `chibiPost` 直接作用于相机帧。
  - Registry 顺序：手绘治愈风、Q 版萌系、2.5D 动画风。中英文案为描述性名称（"Hand-Painted Anime" / 手绘治愈风，"Chibi Pop" / Q 版萌系），不含吉卜力或宫崎骏相关名称，并有单元测试守住这一点。
- 重构：NPR 原有的专用渲染类并入通用 `Rendering/KernelRenderer.swift`（一个 compute kernel + 参数），三种风格与重采样共用；像素缓冲池创建合并为 `MetalContext.makePixelBufferPool`；`PixelBufferTexture` 现在同时持有像素缓冲，防止 GPU 读取期间缓冲被池复用。
- 模型管理：`scripts/convert_animegan.py`（下载官方 `.pb` 并校验 sha256，按三档尺寸转换为 fp16 `.mlmodel`，在 macOS 上做推理冒烟测试）；`docs/MODELS.md`（来源、许可、转换步骤、替代方案）；`.gitignore` 排除所有模型格式与 `.model-cache/`；`project.yml` 设置 `COREML_CODEGEN_LANGUAGE: None`。
- 测试：`InferenceGovernorTests`（档位映射、取已打包的最大尺寸、持续慢帧逐窗降档、偶发慢帧不降、过热降档、不低于最小档、不回升、推理帧尺寸）；`StyleRegistryTests` 新增三风格顺序和商标措辞检查。
- 决策记录（Sunny 可推翻）：
  - **转换走官方 `.pb`，不走 ONNX。** 任务写的是 ONNX → coremltools，但 coremltools 自 6.0 起没有 ONNX 前端，且该 ONNX 图依赖 opset 9 的 `Upsample` 与运行时尺寸。上游 `deploy/pb_to_coreml.py` 已验证 `.pb` 路径，脚本沿用它。同一发布版本、同一模型。
  - **每档一个固定形状模型，不用可变形状。** 固定形状更可能跑在 ANE 上，Linux 上也无法验证可变形状转换；代价是每个风格最多 3 个约 2 MB 的文件。
  - **推理帧用竖屏比例而非 512×512 正方形**，避免画面压扁后再拉伸导致笔触变形；像素量与 S×S 相同，性能预算不变。
- **许可风险（阻断上架带模型的版本）：** AnimeGANv3 仅限非商业用途，商用需作者书面授权（详见 `docs/MODELS.md`）。Chibi 画风没有公开模型。当前 App 不带模型时三种风格都可用（两个 ML 风格走 Metal 回退）。需要 Sunny/用户决定：联系作者取得授权、自训可商用模型，还是 V1 只用 Metal 回退。
- 本机尝试：`.onnx`/`.pb` 下载成功并解析出图签名；PyPI 被出站代理拦截，未能安装 coremltools，**未实际转换出模型**。
- 未编译、未运行（Linux 无 Xcode）。首次在设备上运行时需要重点确认：Core ML 图像输出写入 `outputBackings` 的 BGRA 缓冲正常；A13 上 384 档帧率；降档切换模型时的卡顿时长。
- 下一步：Phase 4 上线打磨（未开始）。

## 2026-10-28 Phase 4 完成（上线打磨，待云端编译验证）
- 图标与启动屏：`scripts/make_placeholder_art.py`（Pillow）生成原创占位图到 `AniReel/Resources/Assets.xcassets`：`AppIcon`（1024×1024，无透明通道，渐变底 + 胶片框 + 星光 + 笔触弧线）、`LaunchMark`（1x/2x/3x）、`LaunchBackground` 颜色。`UILaunchScreen` 使用二者；`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。
- 隐私清单：`AniReel/Resources/PrivacyInfo.xcprivacy`，不追踪、无追踪域名、不收集数据。扫描代码后确认唯一用到的「需声明理由」API 是系统启动时间类（`CACurrentMediaTime`、采集主机时钟），声明理由 35F9.1。未使用 UserDefaults、文件时间戳、磁盘空间、键盘相关 API。
- 不支持机型：`RootView` 接收 `DeviceTier.current`；为 `nil`（A12 及更早）时只显示「此 iPhone 不受支持」页面，中英文案。
- 演示帧源（D4）：新增 `FrameSource` 协议，`CameraSession`（真机默认）与 `DemoFrameSource`（模拟器或无相机设备）两个实现，由纯函数 `FrameSourceKind.select` 选择。演示源用 CoreGraphics 以 30 fps 生成 720×1280 画面（后摄：动态风景，房子在左侧便于看出镜像；前摄：会眨眼的笑脸），送入同一条 StyleEngine → 预览 + ClipRecorder → 相册保存流程。不申请相机权限、不录声音，界面显示「演示画面」标记，并隐藏静音按钮。
- 音频会话（D5）：`AudioSessionPolicy`。关闭采集会话的自动音频配置；预览时 `.ambient` + `mixWithOthers` 且会话不激活，**用户音乐不被打断**，麦克风也不接入。只有在带声音录制开始时才切到 `.playAndRecord` / `.videoRecording` 并把麦克风接入采集会话；离开录制状态时先移除麦克风，再以 `notifyOthersOnDeactivation` 停用会话，让音乐恢复。静音或无麦克风权限时整个录制都不碰音频会话。
  - 随之修正：麦克风接入改为异步，若在麦克风就绪前就按了停止，这段视为空片段，走「过短，请重拍」而不是「录制失败」。
- 空状态与错误态：相机不可用页增加原因说明与「重试」；启动中、实时预览、计时（已录/剩余）有无障碍标签；风格卡片合并为单个无障碍元素；保存成功时发送 VoiceOver 播报。
- 文档：`docs/APPSTORE.md`（中英商店文案草稿、元数据、提交清单，商标规则；字段长度已核对：名称/副标题 ≤30，关键词 ≤100 字节）；`README.md` 重写（风格、约束、目录、构建、演示模式、模型）。
- 测试：`FrameSourceAndAudioPolicyTests`（模拟器/无相机用演示源、真机用相机；演示源不要相机权限、不提供麦克风；预览音频策略可混音且不能录音、录制策略可录音）。不支持机型的判定已由既有 `DeviceTierTests` 覆盖。
- 未做（按指示）：Codemagic 发布工作流、签名、TestFlight。
- 待定事项：隐私政策 URL 与技术支持 URL 为上架必填，尚未建立；正式图标替换占位图；商店截图须用真机拍摄。
- 未编译、未运行（Linux 无 Xcode）。首次云端构建后应在模拟器上手动走一遍演示模式全流程。音频会话行为（不打断音乐、录完恢复）只能在真机上验证。
- 下一步：等待 Sunny 复核；所有阶段（1–4）已完成。
