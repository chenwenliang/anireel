# Phase 7 Brief — 全界面体验重构（用户定向，2026-10-29，决策 D9）

User direction (verbatim essence): 主界面太 low；主界面应显示已经拍好的作品，没有作品时显示默认的三个风格的示例作品；中间是拍摄 icon，两边是重要的辅助功能；点拍摄 icon 后，拍摄页参考抖音（用户附抖音拍摄页截图）；其它界面也需要对应优化。

This phase RESTRUCTURES UI/UX only. All existing logic stays: RecordingMachine, RecordingGate （游客首拍免费）, ClipLibrary, AuthService, Settings/preferences, style packs, demo source. Keep every existing test green; adapt UI tests where the flow changed. zh/en everywhere. No networking, no third-party SDKs.

## Design tokens first
- Create shared design tokens (colors, gradients, radii, typography scale) and use them across ALL screens: aurora gradient (cyan #22C1EE → blue #2F6BFF → violet #8B5CF6), duotone mark gradient (coral #FF6B4A → blue #2F6BFF → violet), coral as the single warm accent, white/light surfaces, Apple-minimal discipline (whitespace, hairlines, soft shadows).
- Fix the AppIcon rendering in scripts/make_placeholder_art.py to match the approved final (D8): NO drop shadow (iOS icons are flat), A with a wider stance and rounded apex, feet rounded (not flat slabs), play triangle larger and optically centered, coral occupying roughly the upper-left 40%.

## Home （主界面） — works first
- Bottom tab shell: 作品 | 风格 | [center camera button] | 示例 | 我的. The center button is a large raised gradient circle with the A mark / camera glyph; it opens the camera.
- 作品 (home): an immersive vertical paging feed of the user's clips from ClipLibrary, newest first, full-bleed looping playback (muted until tapped), with style badge, date, duration, and actions (share, delete, open in My Clips grid). A small top bar: AniReel wordmark left; a quota/status chip (guest: 「免费拍摄剩 1 次」/ used-up state; signed-in: account state) right.
- Empty library → the feed shows exactly THREE sample works, one per style, clearly badged 「示例作品」, each with 「用这个风格拍一条」 CTA that opens the camera with that style preselected. Produce the three sample covers procedurally (extend the art script: painterly abstract covers per style, bundled as assets).
- 风格 tab: style-pack page — large cards per style (sample cover, name, one-line description, 「去拍摄」）, the coming-soon cell, and the last-used style remembered as the camera default.
- 示例 tab: sample works gallery (the same three samples plus per-style explanation), CTA to shoot. （与空状态样品同源。）
- 我的 tab: profile — account header (guest / signed-in + quota status), My Clips (grid, reusing Phase 6), Settings entry, legal, feedback, sign out / delete account (Phase 5/6 functions, restyled).

## Camera screen — Douyin layout (per user's screenshot)
- Full-bleed preview. Top-left: X close (back home). Top-center: current style chip (tap → style panel).
- Right vertical rail (icon + label): 翻转 switch camera, 手电筒 torch (only when available), 麦克风 mute toggle, 倒计时 3s timer toggle, 网格 grid toggle, 设置 camera settings sheet (mirroring etc.).
- Above the shutter: style tab row （手绘治愈风 / Q 版萌系 / 2.5D 动画风）, selected = pill; switching changes the live style (not while recording).
- Bottom row: left 「风格」 button (latest style cover thumbnail) opening the full style panel sheet; center: big record button (white ring; recording state with 30s progress ring + time); right: latest-clip thumbnail → My Clips (or 相册 icon when empty).
- Long-press preview = peek original (Phase 6) stays. Gate check happens on record tap before any countdown (Phase 6 ordering). After save → Result screen (restyled full-screen: playback, share, retake, done, 「已保存到相册 · 已加入我的作品」）.
- Registration wall: when the gate blocks, present it as a sheet over the camera (benefits line + 注册 / 登录 actions + close), not a dead-end screen.

## Restyle the rest to match
- Auth screens (register / login / forgot): same tokens, A mark, white minimal, gradient primary button; copy stays honest about the local V1 implementation.
- Onboarding: update to the new story （刷作品 → 点中间按钮开拍 → 首拍免费）, new palette, still 3 pages, skippable, once.
- Settings & legal: iOS grouped-list style with the tokens; content unchanged.
- Unsupported-device & empty/error states: shared components with the tokens.
- Style picker (Phase 1 screen) is superseded by the 风格 tab + camera style tabs/panel; remove or repurpose the old standalone picker flow so there is exactly one navigation model (tab shell). RootView default = tab shell home （作品）, per D6 default-to-main rule.

## Tests & docs
- New pure-logic tests where logic appears: home content selection (samples iff library empty; ordering), last-used style persistence, tab/camera routing state if modelled purely.
- Update PROGRESS.md （每项决策与理由）, README.md, docs/APPSTORE.md (screenshots/story reflect new UI). Then stop.
