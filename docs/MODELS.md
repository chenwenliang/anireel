# AniReel 模型来源与许可（Models）

模型二进制**不进 git**（`.gitignore` 已排除 `*.mlmodel` / `*.mlpackage` / `*.mlmodelc` / `*.onnx` / `*.pb` / `*.tflite` / `.model-cache/`）。获取方式：`scripts/fetch_models.sh`（一步完成下载 → 校验 → 转换 → 放进工程；Codemagic 构建也执行同一脚本）。

**2026-10-29 起不再有 Metal 回退**：某风格缺模型或模型出错时，拍摄页显示「AI 模型未安装 / 加载失败 / 运行出错」，预览为灰暗的原始画面，且该风格不能录制。三个 `.metal` 近似滤镜仍留在工程里作为独立模块，但没有任何风格使用它们。

## 槽位约定

| 风格 | 槽位名 | 模型 | 状态 |
| --- | --- | --- | --- |
| 手绘治愈风（StyleID `ghibli`） | `animegan_hayao` | AnimeGANv3 官方 `AnimeGANv3_Hayao_36` | 真模型 |
| 2.5D 动画风（StyleID `npr`） | `animegan_shinkai` | AnimeGANv3 官方 `AnimeGANv3_Shinkai_37` | 真模型 |
| Q 版萌系（StyleID `chibi`） | `animegan_chibi` | 无 | 未完成：没有可合法取得的通用场景模型，显示「AI 模型未安装」 |

- 文件：`AniReel/Resources/Models/<槽位>_<512|384|256>.mlmodel`。每个尺寸是独立的固定形状模型：S=512 → 384×680，S=384 → 288×512，S=256 → 192×344（像素量与 S×S 相同的竖屏比例，8 的倍数）。公式在 `InferenceGovernor.frameSize` 与 `scripts/convert_animegan.py` 中各一份，`InferenceGovernorTests` 锁定数值。
- 输入 `AnimeGANv3_input`：RGB 图像，模型内置预处理 `x/127.5 − 1`（App 送入 BGRA `CVPixelBuffer`，Core ML 自动转换）。输出 `image`：RGB 图像，模型内置 `(y+1)·127.5`，App 通过 `outputBackings` 写入自有的 IOSurface 缓冲区。App 按类型找第一个图像输入/输出，不写死名字。
- 起始尺寸 = `DeviceTier.current`（A13 → 384，A14+ → 512），可在拍摄页点模型状态胶囊手动切换尺寸；之后 `InferenceGovernor` 只降不升（30 帧窗口内过半慢于 1/10 秒，或热状态 serious/critical）。
- 计算单元：默认 `.all`；真机对比可用启动参数 `-CoreMLComputeUnits cpuAndNeuralEngine|cpuAndGPU|cpuOnly`。

## 来源：AnimeGANv3 官方发布 v1.1.0

- 仓库：https://github.com/TachibanaYoshino/AnimeGANv3 ；发布页：https://github.com/TachibanaYoshino/AnimeGANv3/releases/tag/v1.1.0 （「The Hayao style and Shinkai style」，说明：「For the .mlmodel, its input is an image of 512*512 size.」）
- 使用的文件（2026-10-29 下载，sha256 固定在脚本里）：

| 文件 | sha256 | 用途 |
| --- | --- | --- |
| `AnimeGANv3_Hayao_36.mlmodel` | `8012cd99b42cc261fd49f491c6c260a1ebdd9502c4694b19a608bc3401cc77b5` | 转换来源 |
| `AnimeGANv3_Hayao_36.onnx` | `95ba7b219073fd5b12f569bc38056ffd3019cf4caf15b1feb9f73d1286c9f69d` | 数值对照 |
| `AnimeGANv3_Shinkai_37.mlmodel` | `7ce2c3aed36c045e5eb6f04336900106edce490355301b15666aa99d54b30d8d` | 转换来源 |
| `AnimeGANv3_Shinkai_37.onnx` | `8dc4d789c44db472447806583c56809e155280225b991bd79f9e2cb20793dcb9` | 数值对照 |
| `inputs/imgs/v3_20.jpg`、`v3_7.jpg`（仓库自带示例照片） | `ab78c175…61191c`、`6edb2d52…0a0647` | 数值对照输入 |

- 官方 `.mlmodel`：neuralnetwork 格式（spec v4），coremltools 6.0 由 TF 1.15 转出，权重 fp32，固定 512×512，作者字段 Asher Chan。

## 许可（2026-10-29 核查官方 README 原文）

- 仓库**没有 LICENSE 文件**（`LICENSE` / `LICENSE.md` / `LICENSE.txt` 均 404），GitHub 不识别标准许可证。唯一条款是 README 的 License 一节，原文：
  > This repo is made freely available to academic and non-academic entities for non-commercial purposes such as academic research, teaching, scientific publications. Permission is granted to use the AnimeGANv3 given that you agree to my license terms. Regarding the request for commercial use, please contact us via email to help you obtain the authorization letter.
- 代码、权重、训练数据：README 不区分，条款覆盖整个仓库及其发布（代码与预训练权重同一条款）。训练数据（宫崎骏 / 新海诚电影截帧）的版权限制 README 未说明，属额外风险，商用前须一并确认。
- **本次用途依据**：「non-academic entities for non-commercial purposes」——用户在自己的 iPhone 上做非商用 POC 测试，属于非商业用途；「such as academic research…」是举例，不是穷举。模型只来自官方发布页，未使用第三方重传。
- **限制**：任何商业分发（App Store、对外 TestFlight，包括免费下载的商业 App）都必须先取得作者授权书（作者邮箱 `asher_chan@foxmail.com`）。另需注意：本 POC 的目的是评估一款计划上架的产品，「为商业产品做的内部评估」是否仍算非商用，条款没有写明——建议尽早邮件作者确认并取得授权，结果记录在此。
- 转换出的模型 metadata 中写有许可说明，便于追溯。

## Q 版萌系：暂无可用模型

- AnimeGANv3 官方能公开下载的**通用场景**模型只有 Hayao、Shinkai（v1.1.0；v1.0.3 另有旧版 Hayao/Shinkai ONNX）。README 提到的 Cute（2023-10-31「Portrait to Cute」）是**人像**模型，且没有公开下载；官方 `AnimeGANv3_Portrait_Inference` 发布的只有 Ghibli-c1（人脸）、PortraitSketch（人像素描）及人脸检测/分割辅助模型，都不适合整幅取景。
- 可选方向：(1) 向作者购买/申请 Cute 等风格的模型与授权；(2) 用可商用数据自训同架构模型；(3) 评估其他有明确许可的轻量模型（需重新做许可与转换核查）。拿到 AnimeGANv3 结构的官方 `.mlmodel` 后，把它加入 `convert_animegan.py` 的 `SOURCES` 即可生成 `animegan_chibi_*`。

## 转换方法

`scripts/fetch_models.sh` → `scripts/convert_animegan.py`：

1. 隔离环境：uv 0.4.30 下载 Python 3.11 到 `.model-cache/python`，venv `.model-cache/venv`，固定 `coremltools==8.3.0`、`numpy==1.26.4`、`onnxruntime==1.19.2`、`pillow==10.4.0`。不需要 TensorFlow / PyTorch。
2. 下载官方 `.mlmodel` 并校验 sha256。
3. 只改与尺寸有关的字段（网络是全卷积的，逐层核查后只有这些写死了 512）：输入/输出图像宽高、外部注意力 `Reshape_1` 的 64×64（= H/8 × W/8）、三个双线性上采样的目标尺寸 128/256/512（= H/4、H/2、H）。权重、层、预处理不动。出现未知层类型或数量不符时脚本退出。
4. macOS 上逐个模型用 Core ML（CPU_ONLY 与 ALL 各一次）推理两张官方示例照片，与官方 ONNX（ONNX Runtime，同尺寸）比较；CPU_ONLY 的平均绝对差大于 1（0–255 像素值，`MAX_MEAN_ABS_DIFF = 1.0`）即失败退出。Linux 上 Core ML 不能运行，跳过此步。

为什么不用 TF `.pb` 重新转换（旧方案）：官方已经提供 Core ML 版本，按需求优先用官方模型；只改尺寸字段比重新经 TF 前端转换改动更小、不引入 TensorFlow 依赖，且结果可与官方 ONNX 逐像素对照。
