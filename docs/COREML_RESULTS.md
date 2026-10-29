# Core ML 风格迁移替换 Metal 着色器：结果报告（2026-10-29）

任务：`docs/COREML_TASK.md`；需求：`docs/POC_SPEC_OPENAI.md`。执行环境：Linux（无 Xcode / Swift 工具链 / iOS 设备）。
**结论先行**：三个槽位中两个已接入真模型（手绘治愈风 = AnimeGANv3 Hayao，2.5D 动画风 = AnimeGANv3 Shinkai），Q 版萌系没有可信模型，如实显示为不可用。模型转换已在本机做了数值验证；**App 代码未编译、未在任何 iOS 设备或模拟器上运行，性能数字一个都还没有**，全部列入下方待测清单。没有触发停止条件。

按需求 3.3，三个目标分开报告：

| 目标 | 状态 |
| --- | --- |
| 1. 模型成功集成 | 转换与数值一致性：本机已验证（见 §3）。在 Core ML 运行时中加载：待 Codemagic（macOS 对照步骤）+ 模拟器 + 真机 |
| 2. 实时处理链路成功 | 代码已完成并人工核查；未编译未运行 → **未验证** |
| 3. 动画化画质达到产品预期 | 只看了官方示例照片的离线输出（§4）；真实摄像头画面 → **未验证** |

## 1. 模型

| 风格 | 模型 | 版本 / 来源 | 状态 |
| --- | --- | --- | --- |
| 手绘治愈风 | AnimeGANv3 `Hayao_36` | 官方 release v1.1.0 的 `.mlmodel`（作者 Asher Chan，coremltools 6.0 / TF 1.15 转出） | 真模型 |
| 2.5D 动画风 | AnimeGANv3 `Shinkai_37` | 同上 | 真模型 |
| Q 版萌系 | — | 官方没有公开的通用场景萌系模型 | **未完成**，显示「AI 模型未安装」 |

- 优先用了**官方 Core ML 模型**（需求 3.1 第 4 条）。官方模型固定 512×512 正方形，而取景是竖屏；所以只改了尺寸相关字段，生成竖屏三档，权重不动（§3）。
- 风格分配：Shinkai 的特点是通透的天空、电影感的光线和写实的动画背景，比萌系更接近「2.5D 动画风」，所以分给 `npr`。原来的副标题「赛璐璐色块、墨线描边与纸张质感」已经不符合实际效果，改为「通透的电影感天空、清亮光线与细致的动画场景」（示例页说明同步修改，中英文都改了）。
- Q 版萌系可选方向：见 `docs/MODELS.md`「Q 版萌系」一节（向作者申请 Cute 等风格及授权 / 自训 / 评估其他有明确许可的模型）。旧 Metal `chibiPost` 不再冒充这个风格。

## 2. 许可依据

- 官方仓库**没有 LICENSE 文件**；唯一的条款是 README 的 License 一节（原文见 `docs/MODELS.md`）：对学术和非学术主体都免费提供，用于**非商业目的**（学术研究、教学、论文只是举例），商用需要邮件取得作者授权书。代码、权重适用同一条款；训练数据（电影截帧）的版权 README 没有说明。
- 本次用途：用户在自己的 iPhone 上做非商用 POC 测试，可以对应「non-academic entities for non-commercial purposes」。模型只从官方 release 下载，并做 sha256 校验，没有用第三方重传。
- **限制与风险**（必须告知用户）：
  - App Store、对外 TestFlight 等任何商业分发，都必须先拿到作者授权书。
  - 本 POC 是在评估一款准备上架的产品。「为商业产品做内部评估」算不算非商用，条款没有写明，属于灰色地带。建议现在就邮件作者（`asher_chan@foxmail.com`）说明用途并申请授权。
  - Codemagic 构建会把模型打进模拟器版 .app。构建产物只上传演示视频，不上传 .app，不构成分发。

## 3. 转换与数值验证

- 方法：`scripts/fetch_models.sh` → `scripts/convert_animegan.py`。
  - 隔离环境：uv 0.4.30 下载 Python 3.11.10，放在 `.model-cache/` 里。
  - 固定依赖：`coremltools==8.3.0`、`numpy==1.26.4`、`onnxruntime==1.19.2`、`pillow==10.4.0`。
  - 不用 PyTorch / TensorFlow：官方已提供 Core ML 模型，不需要重新转换。任务书说的「PyTorch 与 Core ML 对照」，这里用官方 ONNX 作为原模型参照。
- 改动范围：先逐层核查全部 366 层（16 种层类型）。网络是全卷积的，写死了 512 的只有这几处，也只改了这几处：
  - 输入、输出图像的宽高；
  - 外部注意力层 `Reshape_1` 的 64×64，改为 H/8×W/8；
  - 三个双线性上采样的目标尺寸 128/256/512，改为 H/4、H/2、H。
  - 镜像填充、步长 2 卷积的填充量都与尺寸无关；所有池化都是全局池化。
- 产物（本机已生成，gitignored）：`AniReel/Resources/Models/animegan_{hayao,shinkai}_{512,384,256}.mlmodel`，每个约 4.2 MB（fp32），对应 384×680 / 288×512 / 192×344。
- 数值抽查（本机）：Linux 跑不了 Core ML，所以写了一个 NumPy 执行器，逐层按 Core ML spec 的语义执行，再与官方 ONNX（ONNX Runtime 1.19.2）比较。像素值范围 0–255：

| 被测 | 输入 | 平均绝对差 | 最大差 |
| --- | --- | --- | --- |
| 官方 Hayao `.mlmodel` 512×512（验证执行器本身） | v3_20 | 0.0001 | 0.003 |
| 官方 Shinkai `.mlmodel` 512×512 | v3_20 | 0.0002 | 0.003 |
| 改尺寸后 hayao_512（384×680） | v3_20 / v3_7 | 0.0001 / 0.0001 | 0.002 / 0.002 |
| 改尺寸后 hayao_384（288×512） | v3_20 / v3_7 | 0.0001 / 0.0001 | 0.001 / 0.001 |
| 改尺寸后 hayao_256（192×344） | v3_20 / v3_7 | 0.0001 / 0.0001 | 0.001 / 0.001 |
| 改尺寸后 shinkai_512（384×680） | v3_20 / v3_7 | 0.0002 / 0.0001 | 0.001 / 0.001 |

  - 结论：改尺寸后的 spec 与原模型在数学上一致，**停止条件 2 未触发**。
  - 这个检查**不能**代替真正的 Core ML 运行：Core ML 的 fp16（GPU / 神经网络引擎）误差、以及 BGRA 输入/输出的处理，都只能在 macOS 或 iOS 上看到。所以 Codemagic 会在 Mac 上用真实 Core ML（CPU_ONLY 与 ALL 各一次）对照官方 ONNX，CPU_ONLY 平均差大于 1 就让构建失败。**这一步的输出数字还没有看到**，等下一次云端构建。
- 本机检查用的脚本和对比图：`.model-cache/samples/`（`nnexec.py`、`cmp512.py`、`cmpport.py`、`out_*.png`，gitignored）。

## 4. 画质初判（仅离线示例照片）

看的是 `.model-cache/samples/out_animegan_hayao_512_v3_20.png`、`…_v3_7.png`，左原图右输出，384×680：

- 是真正的「重绘」，不是滤镜感：天空和云被画成手绘笔触，水面、石阶变成平涂色块，暗部轮廓是细而柔的深色线。**没有美漫式粗描边**，平坦区域（天空、墙面、石面）干净，没有随机斑点。
- 色彩偏亮、偏淡、偏粉彩，**达不到参考图 `docs/design/style-target-handpainted.png` 那种饱和、浓郁的色彩**。这是这个模型本身的取向（官方示例也一样），不是转换造成的。可以考虑在 Metal 后处理里加一道温和的饱和度 / 自然饱和度调整（需求允许必要的色彩后处理），但必须在真机画面上对比后再决定，本次没有做。
- 树叶等高频细节会变成较碎的色块；256 档明显更糊，只建议作为降温档。
- Shinkai：色彩更通透，偏冷，适合天空和街景。
- 人脸、运动画面、帧间闪烁：**完全没测**。AnimeGANv3 是逐帧模型，没有时序约束，预计会有一定闪烁，需要真机验证。

## 5. App 改动

处理链路（需求 3.2）：AVFoundation 相机帧 → `StyleEngine`（视频队列；在途帧数上限 2，超出直接丢弃，不排队）→ `CoreMLStyleRenderer`：
1. Metal 把相机帧重采样到模型尺寸；
2. Core ML 推理，输入、输出都是 IOSurface BGRA 缓冲区，无 CPU 拷贝；
3. Metal 把输出重采样到 720×1280；
4. 同一个缓冲区同时送预览和录制。

主要改动：
- **不再有着色器回退**：没有模型、加载失败、推理失败、缓冲区不足，都会进入 `StyleModelStatus.unavailable(原因)`。这时：
  - 每帧画成灰暗的原始画面（`styleUnavailable` 内核），并标记为「未风格化」；
  - 拍摄页显示原因胶囊和居中说明；
  - 录制键禁用。如果正在录制，会立即停止，保存已经风格化的部分。
- **未风格化的帧永远不会写进视频**：`StyleRenderer.encode` 现在返回「是否为风格化帧」，`CameraModel` 只把风格化帧交给录制器。
- **模型在每个进程里只加载一次**：同一模型按 URL 缓存；切换风格、切换尺寸都不会重复编译。加载在视频队列上进行，不在主线程。顺带解决了 Phase 7 记录的「切换风格时在主线程加载模型」问题。
- **性能如实统计**：每秒一个窗口，统计这一秒内真正完成的推理次数（FPS），以及推理耗时 P50/P95、预处理 P50。预览重复绘制同一帧不计入。
  - 显示在拍摄页左上角的胶囊里，例如「AI 384×680 · 12.3 fps · 71/95 ms」；
  - 同时写进系统日志（subsystem `com.anireel.app`，category `coreml`），另外记录热状态和内存占用（phys_footprint）。
- **512 / 384 对比**：空闲时点状态胶囊，可在已打包的尺寸间循环切换。
- **计算单元**：默认 `.all`（CPU+GPU+神经网络引擎）。要对比时，在 Xcode 启动参数里加 `-CoreMLComputeUnits cpuAndNeuralEngine|cpuAndGPU|cpuOnly`。
- **降档策略改为画质优先**：`InferenceGovernor.frameBudget` 从 1/30 秒改为 1/10 秒。只有一个窗口里过半帧低于 10 fps，或热状态到 serious，才降一档；不再为了追 30 fps 而自动降到 256。

### 改动文件清单
- 模型运行时：`AniReel/ML/CoreMLStyleRenderer.swift`（重写）、`AniReel/ML/StyleModelStatus.swift`（新）、`AniReel/ML/InferenceGovernor.swift`
- 渲染：`AniReel/Rendering/StyleEngine.swift`、`KernelRenderer.swift`、`Resample.metal`（新增 `styleUnavailable`）、`AniReel/Styles/StylePack.swift`
- 风格包：`AniReel/Styles/Packs/{ghibli,chibi,npr}/*StylePack.swift`；三个 `.metal` 只在文件头加了「不再使用」注释
- 拍摄页：`AniReel/Features/Camera/CameraModel.swift`、`CameraScreen.swift`（只新增状态胶囊、不可用说明和录制键禁用条件，没有改 UI 结构）
- 文案：`AniReel/Resources/{en,zh-Hans}.lproj/Localizable.strings`（新增 9 条，修改 2 条，中英文键集合一致）、`AniReel/Features/Styles/SamplesView.swift`
- 测试：`AniReelTests/StyleModelStatusTests.swift`（新）；`AniReelUITests/DemoFlowUITests.swift`（演示流程改用第三个风格，并等待模型就绪）
- 脚本与 CI：`scripts/fetch_models.sh`（新）、`scripts/convert_animegan.py`（重写）、`codemagic.yaml`（新增模型获取、转换、对照步骤）
- 文档：`docs/MODELS.md`（重写）、`docs/LOCAL_RUN_MAC.md`（加入模型步骤）、本报告、`PROGRESS.md`

## 6. 录制链路确认（代码核查）

- 保存的视频来自 `StyleEngine` 的输出缓冲区，与预览是同一帧，是**风格化后的帧**（需求 4.3）。
- 占位帧、失败后的帧都不会写入。模型不可用时根本不能开始录制。
- 时间戳使用相机帧的原始采集时间。推理慢时写入的帧会少，是真实的可变帧率，**不会重复旧帧来补足帧数**（需求 4.5）。音频使用同一时间线。
- 已知小问题（未改）：`ClipRecorder` 用最后一帧时间 + 1/30 秒作为片尾。低帧率时最后一帧只停留 1/30 秒，片长会比实际按下停止的时刻短最多一帧间隔。
- 以上都还没有经过真机录制验证。

## 7. 性能

**没有任何实测数据。** 本机是 Linux，不能运行 iOS / Core ML。NumPy 执行器的耗时没有参考意义，没有写进报告。

| 项目 | 512 档（384×680） | 384 档（288×512） |
| --- | --- | --- |
| 推理 P50 / P95 | 待真机 | 待真机 |
| 实际输出 FPS | 待真机 | 待真机 |
| 预处理 P50 | 待真机 | 待真机 |
| 计算单元 | `.all`（另测 cpuAndNeuralEngine / cpuAndGPU） | 同左 |
| 内存、热状态、连续运行变化 | 待真机（日志里有） | 待真机 |

模拟器只能用 CPU，帧率不代表真机，只能用来确认「能加载、能推理、能录制」。

## 8. 待验证清单

**Codemagic（下一次推送后）：**
1. 「Fetch, convert and check」步骤里 6 个模型 × 2 张图的 Core ML 与 ONNX 对比数字（CPU_ONLY 应 < 1；ALL 的 fp16 差异也要记下来）。
2. 能编译，单元测试全部通过（含新的 `StyleModelStatusTests`）。
3. 演示视频：手绘治愈风 → 2.5D 动画风都显示模型状态胶囊和实际 fps，录制 4 秒能保存。如果模拟器 CPU 太慢导致片子短于 1 秒，演示步骤会失败（这个步骤允许失败，不会让构建变红），这是性能结论，不是代码错误。

**真机（用户，iPhone 14 Pro，按 `docs/LOCAL_RUN_MAC.md`，记得先执行 `scripts/fetch_models.sh`）：**
1. 手绘治愈风：状态胶囊显示 `AI 384×680 · … fps`。记录 fps 和 P50/P95；点胶囊切到 288×512，再记录一次。
2. 场景：室内地板、墙面、天花板（看平坦区域斑点）；户外建筑、天空、树木；人脸、头发、衣服；缓慢移动和快速转动（看闪烁、拖影）。长按看原图做对照，截屏保存成对样本。
3. 色彩：与参考图对比，判断饱和度是否不足、要不要加后处理。
4. 录一支 10 秒的片子，确认相册里是风格化画面、方向和比例正确、音画同步。
5. 连续运行 5 分钟：热状态、fps 变化、有没有自动降档（胶囊里的尺寸会变）。
6. Q 版萌系：应显示「AI 模型未安装」、灰色画面、录制键不可点。
7. 计算单元对比（可选）：Xcode › Product › Scheme › Edit Scheme › Run › Arguments，加入 `-CoreMLComputeUnits cpuAndNeuralEngine` 或 `cpuAndGPU`，分别记录 fps。
8. 飞行模式下重复第 1 步，确认离线可用（模型在 App 包内，推理不联网）。

## 9. POC 验收状态（需求第七节）

- P0：
  - 真模型集成：代码和模型已就绪，待编译与运行确认。
  - 真机加载与推理、摄像头画面经过 AI 转换、持续显示：**未验证**。
  - 不依赖云端：是，设计上就是本地推理。
  - 不用 Metal 伪装：是，已移除回退路径。
  - 现有功能未破坏：待 Codemagic。账户、作品库、门槛、UI 结构的代码都没有改；录制只新增了「只写风格化帧」这一个条件。
  - 授权条件：个人非商用测试有依据；评估商业产品这一点存在灰色地带，见 §2。
- P1：全部**未验证**（需要真机）。初判（仅离线示例照片）：明显优于滤镜，有日系手绘特征，但色彩饱和度低于参考图。
- 是否建议继续用 Hayao：建议先在真机上验证画质和帧率。主要风险有三个：
  1. 色彩偏淡；
  2. 逐帧模型的闪烁；
  3. 商用必须取得授权书。
  如果色彩问题后处理也无法弥补，下一步可以评估 Hayao 的旧权重（v1.0.3 的 H40/H64 ONNX，需要另走转换流程），或者取得授权后训练 / 微调。
