# AniReel — 实时风格相机（iOS 原生）

选风格 → 摄像头自动开启 → 实景实时变成所选风格拍摄（最长 30 秒）→ 自动保存；中途终止也保存。

第一版风格：
1. 吉卜力系手绘治愈风（Ghibli-style）
2. Q版 / Chibi 风
3. 2.5D / 3D NPR 动画风

风格以独立 StylePack 扩展：新增风格 = 新增一个 Pack，不改核心管线。

- 完整任务书：`PROJECT_BRIEF.md`
- 进度日志：`PROGRESS.md`（每日早上 9 点汇报以此与 git/文件状态为准）
- 平台：iOS 17+ / Swift / SwiftUI / AVFoundation / Metal / CoreML，纯端上处理，不联网、不追踪
