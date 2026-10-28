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

## 2026-10-29 Phase 5 完成（账户 + 拍摄门槛，D6；待云端编译验证）
- 门槛：`Accounts/RecordingGate.swift`。纯函数 `RecordingGate.decide(account:savedGuestRecordings:)`：游客已成功保存 < 1 条则允许，否则需要账户；已登录不限。`GuestUsageCounter` 把游客已保存条数存在 Keychain（重启、重装都保留；不用 UserDefaults，所以隐私清单不变）。
- 计数时机写进录制状态机：只有 `saving → saveSucceeded` 发出新的 `.clipSaved` 副作用；过短丢弃、写入失败、保存失败后丢弃都不会发出。`CameraModel` 收到后调用 `AccountStore.noteClipSaved()`，且只在游客状态下计数。
- 录制按钮改走 `CameraModel.recordButtonTapped()`：门槛不通过时不开始录制，弹出注册页（附原因说明）；注册或登录成功后 `accountProvided()` 立即开始刚才被拦下的录制。
- 账户后端边界：`AuthService` 协议（恢复会话、注册、登录、退出、删除账户、找回密码返回 `PasswordResetRoute`、本机重置）。`LocalAuthService`（actor）：每账户 Keychain 一项，16 字节随机盐 + CryptoKit SHA-256，常量时间比较，记录带 `version` 便于以后升级哈希；会话存 Keychain；不联网、无第三方 SDK。`AccountStore`（`@Observable`）是界面唯一依赖。
- 界面（中英）：注册（邮箱 + 密码 + 确认，提交后逐项显示校验错误，服务错误横幅）、登录、找回密码（输入邮箱 → 说明页；本机实现如实说明「账户只在这台 iPhone 上，不会发邮件」，并可当场设置新密码 → 完成）。主界面右上角账户按钮显示「游客」或邮箱；账户页可注册、登录、退出、删除账户（带确认）。
- 范围外但上架必需，已加入：**App 内删除账户**（准则 5.1.1(v)）。
- 测试：`AccountTests.swift`。门槛（游客第一次允许、第二次拦截、已登录不限、计数跨启动持久、只有成功保存才计数：过短/保存失败后丢弃/写入失败均不计、重试后成功计一次）；`AccountStore` 整合（游客保存后被拦、注册后放行、登录期间保存不计数、退出后再次被拦）；表单规则；`LocalAuthService`（注册即建会话且跨实例恢复、邮箱大小写不敏感去重、错误密码拒绝、存储中无明文密码且盐各不相同、退出、本机重置、删除账户）。`RecordingMachineTests` 中保存成功的期望副作用加入 `.clipSaved`。
- 文档：新增 `docs/ACCOUNTS.md`（行为、结构、存储与安全、已知局限、App Review 风险、隐私影响、后端选型与上线清单）；`docs/APPSTORE.md` 加入账户相关文案与检查项；README 更新。
- **需要 Sunny/用户拍板的风险：**
  1. **App Review 5.1.1 强制注册**：账户除解锁拍摄次数外没有任何账户功能，审核可能拒审。可选：接远程后端提供真实账户价值、改用内购解锁，或在审核备注说明。
  2. **单次加盐 SHA-256 偏弱**（按 D6 指定实现）。本机场景风险有限；建议改 PBKDF2（系统自带 CommonCrypto），服务端用 Argon2id/bcrypt。
  3. 本机门槛可用任意邮箱注册绕过，真正的注册墙需要远程后端与邮箱验证。
- 未编译、未运行（Linux 无 Xcode）。
- 下一步：Phase 6（`docs/PHASE6_BRIEF.md`，D7），已排队。

## 2026-10-29 Phase 6 完成（上线功能补齐，D7 / `docs/PHASE6_BRIEF.md`；待云端编译验证）
- A. 删除账户 + 设置页
  - `AuthService.deleteAccount(password:)`：需重新输入密码，删除该账户 Keychain 记录与会话，回到游客。账户行抽成共用的 `AccountSection`，账户页与设置页都用它。
  - **决策：删除账户不清零本机游客已用次数。** 理由：次数按设备计，否则「注册 → 删除」会无限换取免费次数；从未用过免费次数的用户删除后仍可免费拍一次。已写入 `docs/ACCOUNTS.md`，有测试。
  - 设置页：账户、拍摄默认值（默认摄像头、前置镜像、默认静音；下次打开相机生效）、存储（作品数、占用空间、清空我的作品）、关于（版本、隐私政策、用户协议、发送反馈 mailto 占位 `feedback@anireel.app`）。
  - **决策：偏好设置存为 Application Support 下的 JSON 文件（`Storage/JSONFileStore.swift`），不用 UserDefaults**，隐私清单因此不必新增 UserDefaults 声明；解码对缺失字段回退默认值，便于以后加字段。
- B. 结果页：保存成功（`RecordingPhase.saved`）时全屏展示 `ResultView`：循环播放刚保存的视频、分享、重拍（回到相机，同一风格）、完成（回到主界面）。原「已保存到相册」浮层删除，VoiceOver 播报保留在结果页。关闭结果页发送 `.acknowledged`，状态机不变。
  - `.clipSaved` 副作用改为携带文件 URL：`CameraModel` 先把临时文件复制进作品库，状态机随后的 `.deleteFile` 再删除临时文件。相关测试同步改为 `.clipSaved(url)`，Phase 5 的门槛计数规则不变。
- C. 我的作品：`Library/ClipLibrary.swift`。纯值 `ClipLibraryIndex`（新的在前、按 id 删除、总字节数、对账时剔除文件已不存在的记录）+ `ClipLibrary`（视频副本放 Application Support/AniReel/Clips，元数据 `library.json`）。网格缩略图、点击播放、分享、删除（明确提示不影响相册）、空状态。游客与注册用户都有。
  - **决策：V1 不设容量上限**，总量显示在设置页，可手动清空。
  - **决策：作品目录排除 iCloud 备份**（相册里已有一份，避免重复占用用户 iCloud）。
  - 文件大小在导入时用 `URLResourceKey.fileSizeKey` 读取并记入元数据，没有使用文件时间戳类 API。
- D. 分享：用 SwiftUI `ShareLink` 调起系统分享面板（底层即 UIActivityViewController），结果页与我的作品共用。**决策：** 不另写 UIKit 包装，代码更少、行为相同。
- E. 法律页面：`Resources/{en,zh-Hans}.lproj/PrivacyPolicy.txt`、`TermsOfService.txt`，用极简标记（# / ## / -）由纯函数 `LegalBlock.parse` 渲染。内容与应用一致：端上处理、无网络、无追踪、本机账户、风格名不关联任何工作室。生效日期、开发者名称、联系邮箱为占位。**文本为草稿，不构成法律意见。** `docs/APPSTORE.md` 已注明商店仍需公开托管的隐私政策 URL。
- F. 首次启动引导：3 页（做什么、三种风格、第一次拍摄免费无需账户），可跳过，只显示一次（记在偏好设置），不请求任何权限。风格选择页末尾加不可点击的「更多风格敬请期待」卡片。
- G. 拍摄小功能
  - 3 秒定时：纯函数 `CaptureStart.plan`。**决策：先检查拍摄门槛再倒计时**，游客已用完时直接弹登录，不让用户白等 3 秒。倒计时中再按录制键取消；中断/离开页面也取消。登录后恢复被拦下的录制时同样遵循定时设置。
  - 后置手电筒：`FrameSource.isTorchAvailable()` / `setTorch(_:)`，只在当前摄像头有手电筒时显示；切换摄像头后关闭并重新检测；演示源始终不可用。
  - 网格线：三分线叠加在预览视图上，不进入录制画面。
  - 长按看原图：`PreviewRenderer` 同时保留风格化帧和原始帧，按住时显示原始帧。**决策：录制中也允许**，因为录制器始终写入风格化帧，与预览显示无关，没有风险。
- 测试：`Phase6Tests.swift`（作品库索引排序、删除、总量、对账、JSON 往返；作品库导入/跨实例持久/删除/清空的文件行为；`CaptureStart` 门槛先于倒计时；偏好设置默认值、持久化、旧文件缺字段；删除账户：错误密码拒绝、成功后回到游客且本机次数保留、未用过免费次数时删除后仍可拍；法律文本解析、中英文档都已打包）。更新 `AccountTests` 与 `RecordingMachineTests` 中的 `.clipSaved(url)`。
- 隐私清单：重新扫描需声明理由的 API，仍只有系统启动时间（35F9.1），无需改动。
- 文档：README、`docs/APPSTORE.md`（商店描述、Phase 6 检查项、隐私政策 URL 说明）、`docs/ACCOUNTS.md`（删除账户与次数规则）已更新。
- 待用户/ Sunny 处理：真实反馈邮箱与技术支持 URL；托管隐私政策 URL；法律文本占位项与专业审阅；Phase 5 记录的 App Review 5.1.1 强制注册风险仍未解决。
- 未编译、未运行（Linux 无 Xcode）。下一步：等待复核（Phase 1–6 已完成）。

## 2026-10-29 图标同步为 D8 定稿
- `scripts/make_placeholder_art.py` 改画定稿图案：珊瑚橙 → 电蓝 → 紫的对角渐变底，白色实心圆角 A，中央播放三角镂空透出渐变（形状先画再模糊加阈值，统一圆角），保留轻微投影。AppIcon 1024×1024，RGB 无 alpha。
- LaunchMark（1x/2x/3x）改为同款白色 A + 镂空三角；LaunchBackground 改为深靛紫 `(30, 22, 72)`。
- 已运行脚本重新生成 PNG 与颜色集。渐变色值为按 D8 描述取的近似值，设计稿 anireel-app-icon-final 的精确色值不在仓库内，如有需要再对齐。

## 2026-10-29 Phase 7 完成：全界面体验重构（D9 / `docs/PHASE7_BRIEF.md`；待云端编译验证）
- 设计令牌：`AniReel/DesignSystem/Theme.swift`（极光渐变 #22C1EE→#2F6BFF→#8B5CF6、双色 A 标记渐变 #FF6B4A→#2F6BFF→紫、珊瑚为唯一暖色点缀、浅色表面、细线、柔和阴影、圆角与字号）；`Components.swift`（A 标记、字标、渐变主按钮、次按钮、胶囊标签、共用空/错误状态 `StateMessageView`、风格封面）。所有界面改用令牌。
  - **决策：App 改为浅色（`.preferredColorScheme(.light)`）**，作品流、拍摄页、结果页自绘黑色舞台。理由：简报要求白色/浅色表面；沉浸页面本就需要黑底。
- AppIcon 修正（`scripts/make_placeholder_art.py`）：去掉投影；A 改为宽站姿、圆顶、圆脚（圆角三角并集 + 模糊阈值柔化内角）；播放三角加大，重心落在 A 的竖向中线上；渐变改用令牌色，珊瑚约占左上 40%；A 整体缩到画布 84% 留出边距。同脚本新增：`BrandMark`（白色 A 标记，界面内着色用）、三张示例作品封面 `SampleCover{Ghibli,Chibi,NPR}`（720×1280 JPEG，程序化绘制的手绘田园 / Q 版糖果 / 赛璐璐城市，原创）。
- 导航（唯一模型）：`RootView` → 底部导航外壳「作品 | 风格 | 中央拍摄键 | 示例 | 我的」，默认作品页（承接 D6）；相机以全屏方式盖在任意标签页上。纯值 `ShellState`（`Home/ShellState.swift`）负责全部跳转：中央键开相机、示例 CTA 带风格开相机、关闭保留原标签、结果页「完成」回作品页、最新作品缩略图/作品页按钮 → 关相机并进入「我的 › 我的作品」、再点「我的」回根。
  - 旧的 Phase 1 风格选择页 `StylePickerView` 与主界面账户按钮 `AccountSheet` 已删除（被风格页 + 拍摄页风格页签/面板、「我的」取代）。
  - **决策：中央按钮用相机图标而非 A 标记**，理由：用户一眼看懂是「拍摄」；A 标记用在字标、注册墙、登录页与引导页。
- 作品页：竖向分页作品流（`containerRelativeFrame` + `.paging`），最新在前，只播放当前页，默认静音、点按开声音（整个流共享）；底部风格徽标、日期、时长；右侧动作：声音、分享、我的作品、删除（确认）。顶部字标 + 额度胶囊（游客剩余次数 / 已用完 · 注册 / 已登录），游客点胶囊直接弹注册。
  - 空库时只显示三条示例（`HomeFeed.items`：有任何作品就不混入示例），带「示例作品」徽标与「用这个风格拍一条」。
  - **决策：示例封面是静态插画，页面上明确写「示例为风格示意图，实际成片以实时预览为准」**，理由：没有真机实拍素材，不能把插画冒充成片效果；静态封面加缓慢推近动画（尊重「减弱动态效果」）。
- 风格页：每种风格一张大卡片（封面、名称、一句话描述、「去拍摄」），上次使用的风格带「上次使用」标签，末尾「更多风格敬请期待」。示例页：同一组示例（与空作品流同源 `SampleWork.catalog`）+ 每种风格适合拍什么 + 拍摄按钮。
- 上次使用的风格：`AppPreferences.lastStyleID`（缺字段时为空，旧文件照常读取）；拍摄页每次切换风格即写入，中央拍摄键用 `StyleChoice.resolve`（指定 > 上次 > 第一个；已下架的风格忽略）。
- 我的：渐变账户卡片（游客 / 邮箱 + 额度说明）、我的作品（数量 + 最近 4 条缩略图）、账户操作（注册/登录或退出/删除账户，逻辑沿用 Phase 5/6）、设置、隐私政策、用户协议、反馈。
  - **决策：账户操作从「设置」移到「我的」**，设置页只保留拍摄默认值、存储、关于（内容不变）。理由：两处都放退出/删除会重复；「我的」就是账户入口。设置改为从「我的」推入（不再是带「完成」按钮的弹窗）。
- 拍摄页（抖音布局）：全屏预览；左上关闭（录制/倒计时中隐藏，因离开会结束录制）；顶部风格胶囊（点开风格面板）；右侧竖排工具栏：翻转、手电筒（仅可用时）、麦克风（演示模式隐藏）、倒计时、网格、设置（拍摄设置半屏：前置镜像实时开关 + 小提示）；快门上方风格页签（选中为白色胶囊）；底部左「风格」（当前风格封面，打开风格面板）、中间录制键（白环 + 珊瑚芯，录制时 30 秒进度环，上方显示 已录/30 秒）、右「我的作品」（最新作品缩略图，空库时显示相册图标）。录制/倒计时中工具栏、页签、两侧按钮让位。长按看原图、门槛先于倒计时（Phase 6）不变。
  - 实时切换风格：`StyleEngine.setRenderer` 加锁替换渲染器，下一帧生效；`CameraModel.selectStyle` 只在 `RecordingPhase.allowsStyleChange`（仅 `.ready`）且无倒计时时生效，新渲染器创建失败则保留原风格。保存的作品按「开始录制时」的风格记录。
  - 已知取舍：带 Core ML 模型时切换风格会在主线程加载模型，可能短暂卡顿；当前构建不带模型（Metal 近似）无此问题，接入模型时再移到后台。
  - 注册墙：门槛拦截时以半屏弹层出现在拍摄页上（A 标记、「注册免费账户，继续拍摄」、权益一行、注册 / 登录 / 关闭），注册或登录成功后立即开始被拦下的录制（沿用 `accountProvided()`）。
- 结果页：全屏黑底，圆角回放（带风格徽标），「已保存到相册 · 已加入我的作品」（副本失败时如实说明），重拍 / 分享 / 完成。
- 注册 / 登录 / 找回密码：白底极简页（渐变 A 标记、大标题、圆角填充输入框、渐变主按钮、蓝色文字链接），校验与错误逻辑不变，文案仍如实说明账户只存在本机、不发邮件。
- 引导页：新故事 3 页（刷作品 → 点中间按钮开拍 → 首拍免费），新配色与自绘页码，可跳过、只显示一次、不请求权限。
- 设置与法律页：分组列表 + 令牌背景；法律正文放入白色卡片，内容不变。不支持机型、相机权限、相机不可用、我的作品空状态统一用 `StateMessageView`。
- 中英文案：新增约 45 条，删除 11 条不再使用的旧文案；两种语言键集合一致（脚本核对）。
- 测试：`Phase7Tests.swift`（作品流：空库恰好三条示例且按注册顺序、有作品即不显示示例、最新在前、条目 id 唯一、无封面的风格不出示例；`StyleChoice` 优先级与失效风格；`lastStyle` 默认、跨启动持久、Phase 6 旧文件可读；`ShellState` 全部跳转；`QuotaStatus`；只有空闲时可切风格）。既有测试未改动，涉及的逻辑（状态机、门槛、作品库、AuthService、偏好）接口未变。
- 未编译、未运行（Linux 无 Swift 工具链）；已逐文件人工检查编译风险，需 Codemagic 云端构建 + 单元测试确认。

## 2026-10-29 设计任务：Claude 独立设计稿（与 Sunny 方案并行比较）
- `docs/design/claude-design-board.html`：单文件、内联 CSS/SVG、无外部资源。设计令牌 + 五条版式取舍 + 11 个手机画框：图标、启动、作品页（有作品）、作品页（示例）、拍摄页、注册墙、注册、登录、找回密码、结果页、我的。
- `docs/design/CLAUDE_DESIGN_NOTES.md`：色彩分工、与 Sunny 方案可比的取舍（悬浮胶囊导航、竖向作品进度条、示例与作品视觉区分、额度常显不打扰、注册/登录分段切换、找回密码步骤条、结果页「换个风格再拍」、我的页作品优先），以及若选中本方案、相对 Phase 7 实现需改动的地方（均不涉及录制、门槛、作品库、账户逻辑）。
- 已检查 HTML 标签闭合、无外部引用；本机没有浏览器，未截图预览。

## 2026-10-29 Phase 7.1：按 Claude 设计稿对齐实现（D10；待云端编译验证）
- 底部导航：改为悬浮玻璃胶囊（左右留 12pt、高 56pt），中央拍摄键嵌在胶囊中间并上浮；作品页为深色玻璃，其它页为白色玻璃 + 细线 + 柔和阴影；选中项下方珊瑚小圆点。内容从胶囊下方穿过（列表、滚动页自动留出内边距）。
- 作品流：页面全屏铺到状态栏和胶囊下方，叠加信息按读取到的安全区留白；右侧动作改为玻璃圆钮。新增右缘竖向进度段 `ReelIndicator`：只有 1 页时不显示，最多 7 段，长作品流以当前页为中心滑动窗口。
  - **决策：进度段最多 7 段并滑动**，理由：作品多时整条会超出屏幕高度；7 段在 SE 上也放得下。
- 示例页：左上珊瑚斜角标「示例作品」+ 底部玻璃卡片（「示例 2 / 3」、风格名、风格说明与适合拍什么、「用这个风格拍一条」、示意图说明），与真实作品的极简叠加层明显区分。
- 拍摄页工具栏：每项改为圆钮；开启状态为白色圆底 + 珊瑚图标，关闭为半透明黑底 + 白图标。
- 结果页：新增「下一条换个风格？」胶囊按钮（`StyleChoice.alternatives`：除刚用的风格外的全部风格，按注册顺序）。点按先关闭结果页回到就绪状态，再切换风格（风格只能在空闲时切换，顺序不能反）。
- 注册 / 登录：顶部「注册 | 登录」分段切换取代原来的两条文字链接；A 标记移到导航栏中间；注册页底部加「注册即表示同意」+ 用户协议 / 隐私政策链接（在同一弹窗内推入法律页）；登录页标题改为「欢迎回来」。
- 找回密码：顶部三步条（邮箱 → 在这台 iPhone 上重置 → 完成）。中间一步按后端实际行为显示：本机实现为「在这台 iPhone 上重置」，远程后端返回 `emailSent` 时自动变为「查收邮件」（`PasswordResetStage.resetKind`）。
- 我的：身份卡片加数据行（作品数 / 本周 / 可拍次数，已登录显示 ∞），`ProfileStats` 计算；卡片下方直接是最近 6 条作品的三列网格（标题行「全部 N ›」进入完整网格），没有作品时显示「还没有作品」+ 拍摄按钮。顺序：身份卡 → 作品网格 → 设置/法律/反馈 → 账户操作。
  - **按 D10（Sunny 决策）删除账户仍留在「我的」页**，没有移到 设置 › 账户。设计说明已注明此处与设计稿不同。
- 未纳入本次差异清单、因此未做：注册页密码强度条、登录页「本机账户」提示框（设计稿画了，但「换手机需重新注册」尚未核实 Keychain 是否跨设备同步，不写未经核实的说法）、结果页分享按钮比重拍更宽。
- 中英文案：新增 10 条，删除 2 条被分段切换取代的旧链接文案；两种语言键集合一致。
- 测试：新增 `Phase71Tests.swift`（换风格候选、进度段窗口与边界、本周作品数按日历周计算与额度映射、找回密码步骤与中间步骤命名）。既有测试未改动；录制状态机、门槛、作品库、AuthService、偏好的逻辑与接口未变。
- 未编译、未运行（Linux 无 Swift 工具链），需 Codemagic 云端构建 + 单元测试确认。
- 提醒：`AniReel/Features/Account/AccountSheet.swift` 已在 Phase 7 本地删除；若 GitHub 快照同步同样无法删除文件，远端可能仍留着旧版（它只依赖仍存在的 `AccountSection`，能编译，但属于死代码），可按 StylePickerView 的做法放一个空文件占位。
