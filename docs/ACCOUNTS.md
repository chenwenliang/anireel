# AniReel 账户与拍摄门槛（D6）

## 行为

- 启动直接进入主界面（风格选择页），不强制登录。主界面右上角有账户入口：游客显示「游客」，已登录显示邮箱；点开可注册、登录、退出登录、删除账户。
- 游客可免费完成**一次**拍摄。只有「成功保存到相册」才消耗这次机会；过短被丢弃、写入失败、保存失败后丢弃都不计数。
- 游客已用完免费次数后再点录制：不开始录制，先弹出注册/登录。注册或登录成功后，刚才被拦下的录制立即开始。
- 已登录账户不限次数。退出登录后回到游客状态，已用次数保留（不会因退出登录重新获得免费次数）。
- 删除账户（Phase 6）：在账户页或「设置」中，需重新输入密码确认；删除该账户的 Keychain 记录和会话，回到游客状态。**本机的游客已用次数不清零**：如果本机已用过免费次数，删除后再拍仍需登录；如果从未用过，删除后仍可免费拍一次。理由：次数按设备计，否则「注册 → 删除」可无限换取免费次数。

## 结构

| 部分 | 文件 | 说明 |
| --- | --- | --- |
| 门槛规则 | `Accounts/RecordingGate.swift` | 纯函数 `RecordingGate.decide(account:savedGuestRecordings:)` → `.allowed` / `.requiresAccount`；免费次数常量 `freeGuestRecordings = 1` |
| 游客计数 | `GuestUsageCounter`（同文件） | Keychain 持久化「游客已成功保存的条数」 |
| 计数时机 | `Recording/RecordingMachine.swift` | 状态机只在 `saving → saveSucceeded` 时发出 `.clipSaved` 副作用；`CameraModel` 收到后调用 `AccountStore.noteClipSaved()`（仅游客计数） |
| 门槛检查 | `CameraModel.recordButtonTapped()` / `accountProvided()` | 录制按钮先问门槛；被拦时弹出认证，成功后自动开始录制 |
| 账户后端边界 | `Accounts/AuthService.swift` | `AuthService` 协议：恢复会话、注册、登录、退出、删除账户、找回密码（返回 `PasswordResetRoute`） |
| 本机实现 | `Accounts/LocalAuthService.swift` | actor；账户与会话存 Keychain |
| 存储 | `Accounts/SecureStore.swift` | `SecureStore` 协议 + `KeychainStore`；测试用内存实现 |
| UI 状态 | `Accounts/AccountStore.swift` | `@Observable`，界面只依赖它和 `AuthService` 协议 |
| 界面 | `Features/Account/` | 注册、登录、找回密码（`AuthFlowView`），账户入口与账户页（`AccountSheet`） |
| 表单规则 | `Accounts/CredentialRules.swift` | 邮箱规范化（去空格、小写）与校验；密码至少 8 位且含字母和数字；两次输入一致 |

替换为远程后端：新写一个实现 `AuthService` 的类型（例如 `RemoteAuthService`），在 `AccountStore.live()` 里换掉 `LocalAuthService`。界面与门槛逻辑不需要改。找回密码时远程实现返回 `.emailSent(to:)`，界面自动显示「请查收邮件」；`resetPasswordOnDevice` 对远程实现抛出 `.unsupported`。

## 存储与安全

- 每个账户一个 Keychain 通用密码项：service `com.anireel.accounts`，account = 规范化邮箱，内容为 JSON `{version, salt, hash}`。
  - `salt`：每个账户 16 字节，`SecRandomCopyBytes` 生成。
  - `hash`：CryptoKit `SHA256(salt ‖ UTF-8 密码)`。**密码本身从不存储**，单元测试会检查存储内容中不含密码明文。
  - 比较哈希用常量时间比较。
  - `version` 预留给以后升级哈希方案：登录成功时可以用明文密码重新生成新格式记录。
- 会话：service `com.anireel.session`，只存当前登录邮箱。
- 游客计数：service `com.anireel.usage`。
- 所有项 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`、不同步 iCloud、不迁移到新设备。
- iOS 删除 App 时不会删除 Keychain 项，所以本机账户和游客已用次数在重装后仍然存在。这对门槛是有意的（重装不能重新获得免费次数），代价是用户想彻底清除只能用 App 内「删除账户」。
- 没有网络请求，没有第三方 SDK。

### 已知局限（必须在正式上线前解决或确认接受）

1. **单次加盐 SHA-256 计算很快**，一旦 Keychain 数据被导出，可以被离线暴力破解。这是 D6 指定的方案，本机场景下风险有限（数据只在这台设备上，Keychain 本身受设备加密保护），但不应带到服务器端。改进：本机改用 PBKDF2-HMAC-SHA256（CommonCrypto，系统自带，≥ 600,000 次迭代）；远程后端由服务端用 Argon2id / bcrypt。
2. **本机账户不保护任何数据**，只用于拍摄门槛。拿到这台已解锁 iPhone 的人可以在「找回密码」里直接重设密码，这是本机实现能诚实提供的唯一重置方式，界面上如实说明「账户只在这台 iPhone 上，不会发送邮件」。
3. **门槛可被绕过**：任何人都能用任意邮箱在本机注册，不需要验证。本机方案只是把交互流程做完整，真正的注册墙需要远程后端和邮箱验证。
4. 邮箱未验证，也不会和其他设备同步。

## App Review 风险（需用户拍板）

- **准则 5.1.1(v)**：支持创建账户的 App 必须提供 App 内删除账户。**已实现**（账户页与「设置」中的「删除账户」，需输入密码确认）。
- **准则 5.1.1(i)/(v) 关于强制注册**：Apple 要求「没有实质性账户功能的 App，应允许用户不登录就使用」。当前账户除了解锁拍摄次数之外没有任何账户功能（无云端同步、无跨设备、无内容），审核可能认为这是不必要的强制注册而拒审。降低风险的办法（任选，需决策）：
  - 接入远程后端后提供真实的账户价值（如跨设备恢复、作品云端备份）；
  - 或改为其他解锁方式（如 App 内购买 / 订阅）而不是注册；
  - 或在审核备注中说明账户用途。
- **准则 4.8 Sign in with Apple**：只有在使用第三方或社交账号登录时才强制要求提供 Sign in with Apple。纯邮箱密码账户不触发；但一旦接入 Google/微信等第三方登录，必须同时提供 Sign in with Apple。

## 隐私清单与商店标签影响

- 当前（本机实现）：邮箱和密码哈希只存在设备上，不传到开发者或第三方。按 Apple 定义「收集」指数据离开设备，所以隐私营养标签仍为「未收集数据」，`PrivacyInfo.xcprivacy` 不需要改：Keychain 不属于需声明理由的 API，没有使用 UserDefaults。
- 接远程后端后必须同步更新：
  - `PrivacyInfo.xcprivacy` 的 `NSPrivacyCollectedDataTypes` 增加「邮箱地址」（`NSPrivacyCollectedDataTypeEmailAddress`，关联用户、不用于追踪，用途 App 功能）和「用户 ID」；
  - 商店隐私营养标签从「未收集数据」改为「与你关联的数据：联系信息（邮箱）、标识符（用户 ID）」；
  - 需要隐私政策中写明账户数据的存储地点、保留期限和删除方式；
  - 商店描述中「不联网」的表述要删除或改写；
  - 删除账户必须同时删除服务器端数据（准则 5.1.1(v)）。

## 正式后端上线清单

后端选型（待用户拍板）：

| 选项 | 优点 | 注意 |
| --- | --- | --- |
| Firebase Authentication | 成熟，邮箱验证与重置邮件开箱即用，支持 Sign in with Apple | 需要接入 Google SDK（打破「无第三方 SDK」基线），也可以只用其 REST API；中国大陆访问受限 |
| Supabase Auth | 开源，可自托管，REST API 无需 SDK | 自托管要自己运维；邮件需配置 SMTP |
| 自建（如 Vapor / Node + Postgres） | 完全可控 | 安全实现（哈希、限流、令牌刷新、邮件）全部自己负责 |
| 仅 Sign in with Apple | 无密码、隐私好、审核友好 | 不能覆盖邮箱注册需求；需服务端验证 identity token |

上线前必须完成：

- [ ] 选定后端并实现 `RemoteAuthService: AuthService`；会话令牌存 Keychain（替代当前只存邮箱的会话项）。
- [ ] 注册后**邮箱验证**；未验证账户的处理策略（能否解锁拍摄）。
- [ ] **真正的密码重置邮件**（带过期时间的一次性链接或验证码），重置流程用 Universal Links 或验证码回到 App。
- [ ] 服务端密码哈希用 Argon2id 或 bcrypt；登录、注册、重置接口限流与防撞库。
- [ ] 提供 **Sign in with Apple**（推荐；接入任何第三方登录时为强制）。
- [ ] App 内删除账户同时删除服务器数据。
- [ ] 本机账户迁移策略：已有本机账户的用户首次联网时如何处理（提示重新注册，或用本机邮箱预填注册表单）。
- [ ] 门槛计数是否改为服务端记录（防止通过新邮箱或清除 Keychain 绕过）。
- [ ] 更新 `PrivacyInfo.xcprivacy`、隐私营养标签、隐私政策、商店描述（见上节）。
- [ ] 添加 Associated Domains（重置链接、Sign in with Apple 所需）与对应 entitlement。
