# AniReel 装到你的 iPhone 14 Pro — 一步一步操作手册

路线：你的 Mac + Xcode + 免费个人签名（不花钱）。全程约 15 分钟动手操作，另加 Xcode 下载时间。
每一步都给了「✅ 完成标志」，看到标志再往下走。哪一步卡住，把屏幕截图发给 Sunny。

前提：iPhone 14 Pro 的数据线（USB-C / Lightning 转接看你的 Mac 接口）、你的 Apple ID 和密码、Mac 的开机密码。

---

## 第 0 步：看一眼 Mac 系统

1. 点屏幕左上角  →「关于本机」，记下 macOS 版本。
2. ✅ 完成标志：心里有数即可。macOS 14 或更高最稳；如果系统较老，第 1 步装 Xcode 时 App Store 会自动给你能装的最新版，装不上它会明确提示你先升级系统 —— 真遇到了截图发我。

## 第 1 步：安装 Xcode

1. 打开 App Store，搜索 **Xcode**，点「获取 / 安装」（10 GB 以上，视网速等一会儿）。
2. 装完后打开 Xcode 一次：同意许可协议，等它把组件装完（进度条走完），然后可以先关掉。
3. 打开「终端」（启动台搜「终端」），粘贴这一行回车：
   `xcodebuild -version`
4. ✅ 完成标志：终端输出类似 `Xcode 26.0` 的版本号。
   ⚠️ 如果之后编译时它提示安装 **Metal Toolchain** 组件，点「Install」装上（云端构建第一次也遇到了，正常现象）。

## 第 2 步：装两个小工具（Homebrew + XcodeGen）

都在「终端」里操作。**注意：终端里输入密码时屏幕不会显示任何字符，这是正常的，输完回车即可。**

1. 粘贴 Homebrew 官方安装命令并回车，途中会让你输 Mac 开机密码：
   `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
2. 如果你的 Mac 是 Apple 芯片（M1/M2/M3/M4），安装结束时终端会提示你再执行两行以 `echo` 和 `eval` 开头的命令 —— 原样复制执行（只有新装 Homebrew 才需要）。
3. 验证：`brew --version` 能输出版本号即成功。
4. 装工程生成工具：
   `brew install xcodegen`
5. 装图片生成依赖：
   `python3 -m pip install --user pillow`
   ⚠️ 如果这行报 `externally-managed-environment` 错误，改用：`brew install pillow`
6. ✅ 完成标志：`xcodegen --version` 能输出版本号。

## 第 3 步：下载代码并生成工程

继续在终端里（建议就在默认打开的目录操作）：

1. `git clone https://github.com/chenwenliang/anireel.git`
2. `cd anireel`
3. 生成 App 图标和示例封面图（仓库里不存这些成品图，都是现生成）：
   `python3 scripts/make_placeholder_art.py`
4. 生成 Xcode 工程：
   `xcodegen generate`
5. 打开工程：
   `open AniReel.xcodeproj`
6. ✅ 完成标志：Xcode 打开了 AniReel 工程，左侧能看到 AniReel 的文件树；第 4 步终端输出没有红色报错、第 5 步输出里有 `Created project` 字样。

## 第 4 步：在 Xcode 里登录 Apple ID 并设置签名

1. Xcode 顶部菜单 → **Settings…** → **Accounts** 页 → 左下角「+」→ **Apple ID** → 输入你自己的 Apple ID 登录（免费，不需要付费开发者资格）。
2. 回到 Xcode 主窗口，点最左侧顶部的蓝色 **AniReel** 图标 → 中间 **TARGETS** 列表里选 **AniReel** → 打开 **Signing & Capabilities** 标签页。
3. 勾选 **Automatically manage signing**；**Team** 下拉选带 **(Personal Team)** 的那一项（就是你的名字）。
4. ⚠️ 如果 **Bundle Identifier** 一栏报红或提示已被占用：把它从 `com.anireel.app` 改成一个独一无二的值，例如 `com.chen.anireel`（用你的名字拼音即可），再等几秒让它自动重新生成证书。这只影响测试，不影响 App 功能。
5. ✅ 完成标志：Signing 区域没有红色报错文字。

## 第 5 步：连接 iPhone，开启开发者模式

1. 用数据线把 iPhone 14 Pro 连上 Mac。手机弹出「信任此电脑？」→ 点**信任**，输入手机锁屏密码。
2. 手机上：**设置 → 隐私与安全性** → 拉到最底部 → **开发者模式** → 打开开关 → 手机会重启 → 重启后弹窗点「打开」，再输一次锁屏密码。
   ⚠️ 如果「隐私与安全性」里找不到「开发者模式」：先跳过这步，去做第 6 步点一次 Run，Xcode 会报错并引导你开启，回来补做即可。
3. ✅ 完成标志：开发者模式已打开，Xcode 顶部设备列表里能看到你的 iPhone。

## 第 6 步：运行到真机 🎉

1. 在 Xcode 顶部中间的设备选择器（写着设备名的地方）点开，选**你的 iPhone**。
2. 点左上角 **▶** 按钮（或按 `Cmd + R`）。第一次编译要几分钟，耐心等左上角转圈结束。
3. 如果手机弹出「不受信任的开发者」：到手机 **设置 → 通用 → VPN 与设备管理** → 点你的 Apple ID 条目 → **信任**，然后重新打开 AniReel。
4. ✅ 完成标志：iPhone 桌面上出现 AniReel 图标（蓝紫渐变 + 白色 A），点开能进主界面。
5. 真机验收就从这里开始：点中央拍摄按钮 → 允许相机/麦克风权限 → **拍摄页应该是真实摄像头画面**（不再是模拟器里的 Demo frames 演示画面）→ 切换三种风格看实时效果 → 录一支 4–5 秒的片子 → 结束后应自动保存并跳到结果页。游客第一支免费，正好用来验全流程。

## 第 7 步：日常使用与续期（重要）

- 免费签名 **7 天到期**：到期后 App 会点不开（图标还在、数据还在）。续期方法：把 iPhone 连回 Mac → 打开 AniReel 工程 → 再点一次 ▶ Run，覆盖安装即可，**作品和账户数据不会丢**。
- 以后 Sunny 发布新版时，会先把代码同步到 GitHub。你更新只需在终端里：
  `cd anireel && git pull`
  然后重新生成一次并 Run：
  `python3 scripts/make_placeholder_art.py && xcodegen generate`
  再在 Xcode 里点 ▶。

---

## 卡住时速查

| 现象 | 原因 / 解决 |
|---|---|
| `xcodegen: command not found` | Homebrew 没装好或终端没重开；关掉终端重新打开再试，还不行就重做第 2 步第 1–3 条 |
| pip 报 `externally-managed-environment` | 改用 `brew install pillow` |
| 编译报 Metal Toolchain 缺失 | Xcode → Settings → Components 里安装，或终端执行 `xcodebuild -downloadComponent MetalToolchain` |
| Run 报错 `requires a development team` | 第 4 步的 Team 没选，选 (Personal Team) |
| Run 报错 Developer Mode required | 第 5 步第 2 条，开启开发者模式后重启手机 |
| App 图标是灰的 / 点开闪退提示不信任 | 第 6 步第 3 条，去「VPN 与设备管理」里信任 |
| Bundle ID 报红 | 第 4 步第 4 条，改成 `com.你的名字.anireel` |

以上都解决不了：截图发 Sunny，注明卡在第几步。
