# AniReel 模型来源与许可（Models）

模型二进制**不进 git**（`.gitignore` 已排除 `*.mlmodel` / `*.mlpackage` / `*.mlmodelc` / `*.onnx` / `*.pb` / `*.tflite` / `.model-cache/`）。App 在有无模型时都能编译运行：缺模型时对应风格自动使用 Metal 近似效果。

## 槽位约定

| 风格 | 槽位名 | 文件（放在 `AniReel/Resources/Models/`） | 缺模型时 |
| --- | --- | --- | --- |
| 手绘治愈风（StyleID `ghibli`） | `animegan_hayao` | `animegan_hayao_512.mlmodel`、`_384`、`_256` | Metal `ghibliApprox`（柔化 + 平滑色阶 + 暖色提亮 + 柔和描边） |
| Q 版萌系（StyleID `chibi`） | `animegan_chibi` | `animegan_chibi_512.mlmodel`、`_384`、`_256` | 直接对相机帧跑 Metal `chibiPost`（高饱和 + 粗描边 + 圆润色块） |
| 2.5D 动画风（StyleID `npr`） | 无 | 无 | 纯 Metal，无模型 |

- 每个尺寸是独立的固定形状模型：S=512 → 384×680，S=384 → 288×512，S=256 → 192×344（像素量与 S×S 相同的竖屏比例，8 的倍数）。公式在 `InferenceGovernor.frameSize` 与 `scripts/convert_animegan.py` 中各一份，`InferenceGovernorTests` 锁定数值。
- 输入：RGB 图像（App 送入 BGRA `CVPixelBuffer`，Core ML 自动转换）。输出：名为 `stylized` 的 RGB 图像，App 通过 `outputBackings` 写入自有的 IOSurface 缓冲区。App 按类型找第一个图像输入/输出，不写死名字。
- 起始尺寸 = `DeviceTier.current`（A13 → 384，A14+ → 512），取不超过它的最大已打包尺寸；之后 `InferenceGovernor` 只降不升（30 帧窗口内过半超 1/30 秒，或热状态 serious/critical，每窗口降一档）。
- 只打包部分尺寸也可以；只打包了比本机起始尺寸更大的模型时，该风格用 Metal 回退。

## animegan_hayao：AnimeGANv3 Hayao_36

- 来源仓库：https://github.com/TachibanaYoshino/AnimeGANv3
- 发布版本：v1.1.0 — https://github.com/TachibanaYoshino/AnimeGANv3/releases/tag/v1.1.0
- 转换所用文件：`AnimeGANv3_Hayao_36.pb`，https://github.com/TachibanaYoshino/AnimeGANv3/releases/download/v1.1.0/AnimeGANv3_Hayao_36.pb ，sha256 `58bc25bfeec1375047fb8f1d672a1ba6a7a93c266a3769a86c248374f986cf13`（2026-10-28 下载核对，脚本内固定校验）。
- 图结构（2026-10-28 解析同版本 ONNX 核查）：输入 `AnimeGANv3_input:0`，float NHWC `[1, H, W, 3]`，取值 [-1, 1]；输出 `generator_1/main/out_layer:0`，NHWC，取值 [-1, 1]（tanh）。H、W 须为 8 的倍数。同版本 `.pb` 中这两个张量名均存在。
- **许可核查结果（2026-10-28）：不可直接商用。** 仓库没有标准开源许可证（GitHub API 未识别出 license），README 写明对学术与非学术主体「仅限非商业用途」免费，商用须邮件联系作者获取授权书（"Regarding the request for commercial use, please contact us via email to help you obtain the authorization letter."）。
- 风险：AniReel 以上架 App Store 为目标，属于商业分发（即使免费下载）。**未取得作者书面授权前，不得把该模型打包进提交 App Store 的版本。** 开发与内部 TestFlight 测试同样建议先取得授权或仅限本机试验。
- 替代方案（按推荐顺序）：
  1. 邮件联系作者取得商用授权书，存档后在此记录授权范围与日期。
  2. 用许可可商用的数据与代码自训同架构模型（AnimeGANv3 训练代码同样受上述条款约束，需另选 MIT/Apache 训练框架与可商用画风数据集）。
  3. 不带模型发布：手绘治愈风使用 Metal 近似效果（已实现，App 当前默认行为）。

## animegan_chibi：暂无公开模型

- AnimeGANv3 官方发布只有 Hayao、Shinkai 两种画风（v1.1.0）；README 提到的 Cute 等画风没有公开下载（2026-10-28 核查 releases 页面）。
- 现状：槽位已就绪，未打包模型，Q 版萌系使用 Metal `chibiPost` 回退。
- 获取途径：同 Hayao 的替代方案 1、2。拿到 AnimeGANv3 架构的 `.pb` 后执行 `python scripts/convert_animegan.py --pb <file>.pb --name animegan_chibi`；其他架构需改写脚本的输入输出处理。

## 转换步骤

1. Python 3.10 虚拟环境：`pip install "coremltools==7.2" "tensorflow==2.12.*" "numpy<2" pillow`（Apple 芯片 Mac 用 `tensorflow-macos==2.12.*`）。
2. `python scripts/convert_animegan.py`：下载并校验 `.pb`（缓存在 `.model-cache/`），生成三个尺寸的 `.mlmodel`（neuralnetwork 格式，权重 fp16，约 2 MB/个），写入 `AniReel/Resources/Models/`。
3. 在 macOS 上运行时，脚本自动对每个模型做一次推理冒烟测试（检查输出尺寸）；Linux 上只能转换，不能推理。
4. `xcodegen generate`：Xcode 编译时把 `.mlmodel` 编译成 `.mlmodelc` 放进 App 根目录（`COREML_CODEGEN_LANGUAGE: None`，不生成 Swift 类），运行时按名字加载。
5. 云端构建（Codemagic）默认不带模型，构建和测试不依赖模型存在。

为什么不用 ONNX：coremltools 自 6.0 起已移除 ONNX 前端；该 ONNX 导出使用 opset 9 的 `Upsample`，尺寸在运行时计算，经 onnx2torch 等工具中转风险高。上游 `deploy/pb_to_coreml.py` 已验证 `.pb` → Core ML 路径，本脚本沿用它，只把尺寸改成竖屏三档并加了校验。

## 本机（Linux）尝试记录（2026-10-28）

- `.onnx` 与 `.pb` 可从 GitHub 下载，校验通过（下载到会话临时目录，未放入仓库）。
- PyPI 被本机出站代理拦截（`pip install` 报 ProxyError），coremltools / tensorflow 无法安装，**本机未实际转换出模型**。转换需在可访问 PyPI 的机器（Mac 或 Codemagic 前置步骤）上执行，且须先满足上面的许可条件。
