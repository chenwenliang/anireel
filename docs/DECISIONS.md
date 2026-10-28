# AniReel 决策记录（Sunny 代决策，用户授权 2026-10-28）

## D1 兼容性（2026-10-28）
- 最低系统：**iOS 18**（取代任务书初版 iOS 17）。依据：2026-09 市场份额 iOS 26 约 74.6% + iOS 27 约 16.3% + iOS 18 约 7.1%，iOS 18 以上合计约 98%；iOS 17 已在个位数残余内，为其保留兼容的测试/API 成本不划算。
- 机型硬底线：**A13 及以上 = iPhone 11 / 11 Pro / SE(第2代) 及以后**。依据：Apple 在 iOS 26 已砍掉 A12 机型（iPhone XS/XS Max/XR 止步 iOS 18），且 iPhone 11 是能运行 iOS 26/27 的最老机型，A13 是当前生态的分界线。
- 性能分级（DeviceTier）：A13 档推理分辨率 384 降档保实时；iPhone 12 起（A14+）512 全档、目标 30fps；iPhone 14 Pro（A16，用户真机）为基准调试机型。
- A12 及以下不支持：其实时风格化（512 CoreML 推理）掉帧风险高，且已被 Apple 生态淘汰。
- 说明：App Store 无法按芯片直接过滤机型，落地方式 = Deployment Target iOS 18 + 应用内 DeviceTier 判定与降档 + 商店文案注明支持机型。

## D2 无 Mac 的构建/发布路线（2026-10-28）
- 背景：Sunny 本机为 Linux（无 Xcode），用户也没有 Mac。iOS 构建必须在 macOS 上完成，故采用云端 Mac CI，本机/用户均无需购置 Mac。
- 主路线：**Codemagic**（云端 Mac mini M2/M4）。依据：个人账号每月 500 分钟免费 macOS M2 构建时长（每月重置）；接入 App Store Connect API Key 后可自动管理证书与描述文件、自动签名并上传 TestFlight。
- 备选路线：GitHub Actions macOS runner + fastlane（公开仓库免费，私有仓库 macOS 约 $0.062/分钟）。
- 费用与时点：开发期用 Codemagic 免费额度做未签名 Simulator 编译验证，**此阶段不需要 Apple Developer Program**；到 TestFlight 阶段才需要用户以本人 Apple ID 加入 Apple Developer Program（$99/年，签名与 TestFlight 的硬性要求，任何路线都绕不开）。
- 用户配合清单（仅在对应阶段需要，现在不需要做任何事）：
  1. 注册/授权 Codemagic 连接代码仓库（浏览器操作，约 5 分钟，Sunny 逐步引导）。
  2. TestFlight 前：以本人 Apple ID 加入 Apple Developer Program 并付 $99/年（本人身份与付款，必须用户本人完成）。
  3. 在 App Store Connect 生成 API Key 并按引导填入 Codemagic（密钥不经聊天传递）。
  4. 真机验收：用其 iPhone 14 Pro 装 TestFlight 版本，实测实时风格效果、帧率与保存流程并反馈。
- 工程含义：仓库需包含 `codemagic.yaml`（Phase 4 落地）：xcodegen generate → 未签名 simulator build（开发期）/ 签名 archive + 上传 TestFlight（发布期）；project.yml 的签名设置保持 CI 可注入。

## D3 Phase 1 复核后的决策（2026-10-28，Sunny 复核 Claude Code 产出后）
- Phase 1 已完成并经 Sunny 复核（结构与任务书一致，PROGRESS.md 有完整记录）；未编译验证的风险（Swift 并发 @Sendable 回调警告、ForEach 存在类型键路径）接受并顺延到首次云端编译时集中处理，不在无编译环境的本机猜测修复。
- 前置摄像头：**纳入 Phase 2**（与录制闭环一起做前后摄切换 + 前置镜像开关）。理由：风格相机尤其 Chibi 风的核心场景是自拍，缺前置属于功能缺口，不能留到上线前补。

## D4 先模拟、真机推迟（2026-10-28，用户明确指示）
- 用户指示：暂时不需要任何装到真实 iPhone 的方式，先模拟。即日起开发与验证以**模拟器/云端未签名构建**为准，Apple Developer Program（$99/年）、App Store Connect API Key、TestFlight 全部推迟，直到用户主动重开此话题，不再主动提醒催办。
- App Store Connect 无官方模拟环境（已向用户说明）：替代做法是发布管线两段式——开发模式（只编译、出产物、不签名不上传）默认启用，发布模式（签名+TestFlight）等真实 Key 到位再打开，`codemagic.yaml` 在 Phase 4 按此落地。
- 工程含义（验证补强）：iOS Simulator 没有相机输入，故需一个**演示帧源**（内置测试画面/视频帧喂入同一条 StyleEngine 管线），使「风格化→预览→录制→保存」全链路能在模拟器端到端验证；真实帧率与相机效果只能等真机阶段验证，此限制须在汇报中如实标注。

## D5 Phase 2 复核裁决（2026-10-28，Sunny）
- **相册权限退回 `.addOnly`，V1 放弃自定义专辑**（推翻 Phase 2 的 .readWrite 实现）：只存入系统相册主库。理由：本产品隐私原则是最小权限，一款只负责保存的相机应用向用户索取照片读取权限，观感与 App Review 风险都差；专辑只是锦上添花，核心需求「自动保存到相册」不受影响。失败保留临时文件 + 重试的 UX 保留；Info.plist 恢复 `NSPhotoLibraryAddUsageDescription`。
- 音频会话：接受 Phase 2 现状（开相机页暂停用户音乐），**Phase 4 必改**：手动配置 `AVAudioSession`——预览（未录制）时混音不打断音乐，录制开始才切到录制会话。
- GitHub 仓库（用户 2026-10-28 建立）：https://github.com/chenwenliang/anireel （空仓、公开）。本机出站 SSH 被代理拦截（22/443 均重置），推送改走 HTTPS + 细粒度 PAT（仅限 anireel 仓、Contents 读写，经 Secure Vault 录入，不经聊天）。Codemagic 接入时同样连此仓库。
- 代码仓库：VCO 初始化 git（由 Sunny 执行），为 Codemagic 接入做准备；远程仓库待用户账号阶段再推。
