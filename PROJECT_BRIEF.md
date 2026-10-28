# AniReel 任务书（给 Claude Code / 协作者）

## 1. 产品定义（用户已确认，2026-10-28）
iOS 原生 APP。用户打开应用 → 选择拍摄风格 → 选择后自动开启摄像头 → 拍摄时实景实时变为所选风格（预览与成片一致，所见即所得）→ 最长 30 秒，到时自动结束并自动保存 → 用户中途随时终止，终止时也保存已拍部分。
项目名由 Sunny 定为 **AniReel**；目录代号 VCO。目标：达到可上线（App Store 可提交）标准。

## 2. 第一版风格（仅三种，架构可扩展）
1. `ghibli` 吉卜力系手绘治愈风
2. `chibi` Q版 / Chibi 风
3. `npr` 2.5D / 3D NPR 动画风
扩展方式：实现 `StylePack` 协议 + 在 `StyleRegistry` 注册一条；新 Pack 放在 `Styles/Packs/<id>/`，核心拍摄管线零改动。

## 3. 已定决策（用户授权 Sunny 中途决策，2026-10-28；如需推翻须有更强理由并记录在 PROGRESS.md）
- 最低系统 iOS 18（2026-10-28 兼容性决策，见 docs/DECISIONS.md）；Swift 5.9+；SwiftUI 界面；iPhone 竖屏优先。
- 机型分级：硬底线 A13 及以上（iPhone 11 / 11 Pro / SE 第2代起）；A13 档推理降档 384，A14 及以上（iPhone 12 起）512 全档；A12 及以下（iPhone XS/XR 及更早）不支持。工程需含 `DeviceTier` 判定（按机型标识/芯片代次）供 StyleEngine 选档。
- 工程生成：以 XcodeGen 的 `project.yml` 为工程源（本机为 Linux、无 Xcode；最终编译/TestFlight 在 Mac 上 `xcodegen generate` 后用 Xcode 完成）。Bundle ID 占位 `com.anireel.app`，上线前可改。
- 管线：`AVCaptureSession`（VideoDataOutput）→ `StyleEngine`（当前 StylePack）→ 同一份风格化 `CVPixelBuffer` 分发到 Metal 预览（MTKView）与 `AVAssetWriter` 录制，保证预览=成片。
- 推理分辨率 512（AnimeGANv3 在 iPhone 14 上 512×512 可达约 50 FPS 的公开数据为依据）；录制输出 720×1280@30fps（风格化帧上采样）；设备发热/掉帧时自动降档 512→384。
- 风格实现：
  - ghibli：CoreML 槽位加载 AnimeGANv3 Hayao 类模型（模型文件单独放入 `Resources/Models/`，代码提供加载器与缺失模型时的 Metal 近似回退：柔化+色板量化+描边；模型许可须在 `docs/MODELS.md` 记录核查结果）。
  - chibi：CoreML 槽位（第二模型）+ Metal 后处理（高饱和、粗描边、圆润色块）；与 ghibli 共用推理基座、不同 Pack 配置。
  - npr：纯 Metal 着色器（色彩量化/Posterize + Sobel 描边 + 纸纹理叠加），无 ML，确定性输出。
- 音频：带麦克风音轨；麦克风权限被拒时无声录制不阻塞；界面提供静音开关。
- 时长：硬上限 30.0 秒（`RecordingController` 计时，到时自动 finish）；最短有效时长 1 秒，低于 1 秒提示重拍且不保存。
- 保存：`PHPhotoLibrary` 保存到系统相册并建 AniReel 专辑；自动保存失败要提示并保留临时文件可重试。
- 权限：相机（必需）、麦克风（可选）、相册添加（必需，保存时请求）；拒绝时有引导去设置页的空状态 UI。
- 隐私：纯端上处理、无网络请求、无第三方 SDK、无追踪；提供 `PrivacyInfo.xcprivacy` 与中英双语权限文案。

## 4. 上线标准（验收）
- 功能：三风格可切换、自动开摄像头、实时预览风格化、30 秒自动停、中途停保存、自动保存到相册，全部走通。
- 工程：XcodeGen 可生成工程；Release 配置无警告阻塞；Info.plist 权限文案齐全；App Icon 规格与占位资源齐全；隐私清单齐全。
- 质量：核心纯逻辑（StyleRegistry、RecordingTimer/DurationGuard、StylePack 清单解析）有单元测试；录制管线有错误处理（中断、来电、切后台自动终止并保存）。
- 文档：README、docs/ARCHITECTURE.md、docs/MODELS.md（模型来源与许可）、docs/APPSTORE.md（提交清单）。

## 5. 分阶段（每阶段是一个可验证单元，完成即更新 PROGRESS.md）
- Phase 1：工程骨架（project.yml、目录结构、App 入口、权限管理、风格选择页、相机预览原始管线、StylePack 协议与 Registry、NPR 着色器风格可跑通预览）。
- Phase 2：录制闭环（AVAssetWriter、30 秒上限、中途终止、自动保存到相册、录制 UI：计时/进度环/停止）。
- Phase 3：ML 风格（CoreML 加载器、ghibli/chibi Pack、降档策略、模型缺失回退）。
- Phase 4：上线打磨（图标/启动屏、空状态与错误态、无障碍、单元测试、隐私清单、App Store 提交清单文档）。

## 6. 硬约束
- 永不开启 usage credits；套餐限额（Current session / This week）到 100% 即停等重置（此条约束 Sunny 与一切自动化，Claude Code 会话亦同）。
- 不引入付费第三方 SDK；模型与素材必须许可可商用或在 MODELS.md 中标注风险与替代方案。
- 「吉卜力」仅作风格描述，APP 名称、图标、商店文案不得使用吉卜力工作室商标/角色形象。
