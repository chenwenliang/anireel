# AniReel App Store 提交清单与商店文案草稿

状态（2026-10-29，Phase 7 界面已同步）：草稿。签名、TestFlight、App Store Connect 均按 D2/D4 暂缓，等用户重开话题并提供 App Store Connect API Key 后再执行下面的「提交」部分。

## 商标与措辞规则（所有商店文案、截图、图标适用）

- 只用描述性风格名：手绘治愈风 / Hand-Painted Anime，Q 版萌系 / Chibi Pop，2.5D 动画风 / NPR Anime。
- 不得出现：吉卜力、Ghibli、宫崎骏、Hayao、Miyazaki、任何工作室、电影或角色名称；不得出现 Disney、Pixar 等第三方品牌；不得用第三方作品截图做演示画面。
- 图标为 D8 定稿：珊瑚橙→电蓝→紫双色渐变底、白色圆角 A、中央播放三角镂空（`scripts/make_placeholder_art.py` 生成，扁平无投影）。三张示例作品封面同脚本程序化绘制，原创、不含第三方形象。
- 关键词不得包含竞品或第三方商标（App Review 准则 2.3.7）。
- 单元测试 `StyleRegistryTests.testStyleTitlesAvoidStudioTrademark` 检查 App 内风格名称。

## 商店文案草稿

### 简体中文

- 名称（≤30）：AniReel 动画风相机
- 副标题（≤30）：实时把生活拍成动画短片
- 推广文本（≤170）：点中间的拍摄键，选一种画风，眼前的世界立刻变成动画。最长 30 秒，拍完自动存进相册，主页就能刷到自己的作品。
- 描述：
  > AniReel 是一款实时风格化相机。打开就能刷到自己拍的动画作品；点中间的拍摄键，在快门上方切换画风，取景画面当场变成动画效果，你看到的就是最终存下来的视频。
  >
  > 三种画风：
  > · 手绘治愈风：柔和的手绘光影、温润线条与田园暖色。
  > · Q 版萌系：粗描边、糖果色与圆润色块。
  > · 2.5D 动画风：赛璐璐色块、墨线描边与纸张质感。
  >
  > 拍摄方式：
  > · 每段最长 30 秒，时间到自动结束；中途停止也会保存。
  > · 自动保存到系统相册；保存失败时视频暂存在本机，可重试。
  > · 支持前后摄像头切换与前置镜像、3 秒定时、网格线、后置手电筒，录音可一键静音。
  > · 拍完立即回放，可分享；主页竖滑浏览全部作品，「我的作品」网格随时回看。
  >
  > 第一次拍摄无需注册；之后注册免费账户即可不限次数拍摄。
  >
  > 隐私：所有处理都在你的 iPhone 上完成。AniReel 不联网、不收集数据、不追踪，只申请保存到相册的权限，不读取你的其他照片。
  >
  > 支持 iPhone 11、iPhone SE（第 2 代）及更新机型，需要 iOS 18 或更高版本。
- 关键词（≤100 字节）：动画,动漫,卡通,相机,视频,滤镜,Q版,手绘,赛璐璐,风格化,短视频,特效

### English

- Name (≤30): AniReel: Anime Style Camera
- Subtitle (≤30): Film life as a live cartoon
- Promotional text (≤170): Tap the centre button, pick a look, and the world in front of you turns animated. Up to 30 seconds, saved to Photos, and right there in your feed.
- Description:
  > AniReel is a real-time style camera. Open it to swipe through your own animated clips; tap the centre button and switch looks right above the shutter. Your scene is stylized live, and what you see is exactly what gets saved.
  >
  > Three looks:
  > • Hand-Painted Anime: soft painted light, gentle lines and warm countryside colors.
  > • Chibi Pop: thick outlines, candy colors and rounded shapes.
  > • NPR Anime: flat cel shading, ink outlines and paper grain.
  >
  > How it records:
  > • Clips run up to 30 seconds and stop on their own. Stop early and the clip is still saved.
  > • Clips save to Photos automatically. If saving fails, the clip stays on your phone so you can retry.
  > • Front and back cameras, front-camera mirroring, a 3-second timer, a grid, the back-camera torch and a one-tap mute.
  > • Watch each clip right after recording, share it, swipe through all of them on the home feed, or browse the My Clips grid.
  >
  > Your first recording needs no sign-up. After that, create a free account for unlimited recordings.
  >
  > Privacy: everything happens on your iPhone. AniReel makes no network requests, collects no data and does no tracking. It only asks to add videos to Photos and never reads your other photos.
  >
  > Requires iPhone 11, iPhone SE (2nd generation) or newer, and iOS 18 or later.
- Keywords (≤100 bytes): anime,cartoon,toon,camera,video,filter,chibi,cel,painted,stylize,effect,live

文案注意：当前不带 ML 模型的构建中，手绘治愈风与 Q 版萌系使用 Metal 近似效果（见 `docs/MODELS.md`）。上架前用实际构建核对描述是否与效果相符，不要宣传「AI」或特定模型。

## App Store Connect 元数据

| 项目 | 取值 |
| --- | --- |
| Bundle ID | `com.anireel.app`（占位，上线前确认） |
| 主类别 / 次类别 | 摄影与录像（Photo & Video） / 娱乐（Entertainment） |
| 价格 | 免费（待定） |
| 年龄分级 | 按问卷全部选「无」，预期最低档（4+） |
| 隐私营养标签 | 「未收集数据」（Data Not Collected）。本机账户的邮箱只存在设备上，不算收集；接入远程账户后端后必须改（见 `docs/ACCOUNTS.md`） |
| 追踪 | 否（`PrivacyInfo.xcprivacy`：`NSPrivacyTracking = false`） |
| 加密出口合规 | 不使用非豁免加密（Info.plist `ITSAppUsesNonExemptEncryption = false`） |
| 设备 | 仅 iPhone（`TARGETED_DEVICE_FAMILY = 1`），iOS 18.0+ |
| 隐私政策 URL | **必填，待建**：App 内已有隐私政策页（`Resources/<lang>.lproj/PrivacyPolicy.txt`），但商店仍需一个公开托管的 URL，可直接托管同一文本 |
| 技术支持 URL | **必填，待建** |

## 提交前检查清单

工程（可在云端未签名构建中验证）：
- [ ] `xcodegen generate` 成功；Codemagic `ios-simulator-dev` 构建与单元测试全绿。
- [ ] Release 配置构建无警告阻塞（首次云端编译时集中处理 D3 记录的并发警告）。
- [ ] `Assets.xcassets/AppIcon` 1024×1024、无透明通道、无投影（D8 定稿，Phase 7 修正造型）；如有设计稿精确色值，核对 `Theme.swift` 与脚本中的色值。
- [ ] 启动屏：`UILaunchScreen` 使用 `LaunchBackground` 颜色与 `LaunchMark` 图片。
- [ ] `PrivacyInfo.xcprivacy` 打进 App 包：不追踪、不收集数据；声明系统启动时间 API（`CACurrentMediaTime` / 采集时钟，理由 35F9.1）。上传后检查 App Store Connect 的隐私报告无缺漏。
- [ ] Info.plist 权限文案中英齐全：相机、麦克风、相册添加（`NSPhotoLibraryAddUsageDescription`）。
- [ ] 无网络请求、无第三方 SDK。
- [ ] 模拟器端到端（D4 演示帧）：三种风格预览、录制 30 秒自动停、中途停止保存、过短提示重拍、保存到相册、保存失败重试/丢弃。

账户（D6，详见 `docs/ACCOUNTS.md`）：
- [ ] App 内可删除账户（准则 5.1.1(v)）：已实现（「我的」页，需输入密码），提交前在模拟器验证。
- [ ] **强制注册风险（准则 5.1.1）**：账户目前只用于解锁第二次及以后的拍摄，没有其他账户功能，审核可能拒审。提交前需决定：接远程后端提供真实账户价值、改用其他解锁方式，或在审核备注中说明。
- [ ] 审核备注提供测试账户（本机实现可现场注册，说明「账户仅存于设备」即可）。
- [ ] 若接入第三方登录，同时提供 Sign in with Apple（准则 4.8）。

Phase 6 功能（模拟器可验证）：
- [ ] 首次启动显示 3 页引导，可跳过，只出现一次；引导页不请求任何权限。
- [ ] 保存成功后出现结果页：循环播放、分享（系统分享面板）、重拍、完成回到主界面。
- [ ] 我的作品：缩略图网格、播放、分享、删除（提示不影响相册）、空状态。
- [ ] 我的：账户卡片（游客 / 已登录 + 额度）、我的作品、设置、隐私政策、用户协议、反馈、注册/登录或退出/删除账户。设置（从「我的」进入）：拍摄默认值（下次打开相机生效）、存储（数量与占用、清空）、版本、法律页面、反馈邮件。
- [ ] 拍摄小功能：3 秒定时（游客已用完时先要求登录，不先倒计时）、后置手电筒（前置与演示模式隐藏）、网格线（不进成片）、长按看原图（不影响录制）。
- [ ] 隐私政策与用户协议正文中的占位项（生效日期、开发者名称、联系邮箱）发布前填写；文本为草稿，非法律意见，建议上线前请专业人士审阅。
- [ ] 反馈邮箱 `feedback@anireel.app` 为占位，需替换为真实可收信的地址（技术支持 URL 同样必填）。

Phase 7 界面（D9，模拟器可验证）：
- [ ] 启动默认进入底部导航的「作品」页；底部为 作品 | 风格 | 中央拍摄键 | 示例 | 我的。
- [ ] 作品库为空时作品页只显示三条「示例作品」（每种风格一条），「用这个风格拍一条」以该风格打开相机；拍出第一条后示例消失，只显示自己的作品（最新在前，静音自动播放，点按开声音）。
- [ ] 作品页右上角额度胶囊：游客「免费拍摄剩 1 次」/ 已用完「免费次数已用完 · 注册」/ 已登录。
- [ ] 拍摄页：左上关闭、顶部风格胶囊、右侧工具栏（翻转 / 手电筒 / 麦克风 / 倒计时 / 网格 / 设置）、快门上方风格页签（录制中不可切换）、左下风格面板、右下最新作品缩略图。
- [ ] 游客用完免费次数后点录制：拍摄页上弹出注册墙（注册 / 登录 / 关闭），不会先倒计时。
- [ ] 上次使用的风格在下次点中央拍摄键时默认选中。

模型与许可：
- [ ] 若打包任何 ML 模型，`docs/MODELS.md` 中已记录商用授权；否则确认构建内无 `.mlmodelc`。

真机验收（推迟至 D4 解除后）：
- [ ] iPhone 14 Pro 实测三种风格帧率、发热降档、前置镜像方向、来电与切后台中断保存、播放音乐时打开相机不打断音乐、录制结束音乐恢复。
- [ ] A13 机型（iPhone 11 / SE 2）实测 384 档表现。

商店素材：
- [ ] 截图建议顺序（Phase 7 界面）：① 作品页竖滑作品流 ② 拍摄页（抖音式布局、快门上方风格页签）③ 三种风格对比（风格页卡片）④ 结果页「已保存到相册 · 已加入我的作品」⑤ 我的（作品网格 + 账户）。空库时的示例封面是示意插画，不得当作实拍效果用于截图。
- [ ] 截图：6.9 英寸 iPhone（1320×2868 或 1290×2796）。必须用真机实拍画面，**不能使用模拟器演示帧截图**（画面带「演示画面」标记，且不代表真实效果）。
- [ ] 截图与预览视频中不出现第三方作品、商标或可识别的他人肖像（未获授权）。
- [ ] 中英文名称、副标题、关键词、描述、推广文本按上文填写并核对字数。

提交（D2/D4 解除后）：
- [ ] 用户本人加入 Apple Developer Program。
- [ ] App Store Connect 创建 App 记录、生成 API Key 并录入 Codemagic（密钥不经聊天）。
- [ ] 新增 Codemagic 发布工作流（签名 archive + 上传 TestFlight），开发工作流保持不变。
- [ ] TestFlight 内测通过后提交审核；审核备注说明：纯端上处理、无网络、账户仅存于设备（或按远程后端实际情况改写）。
