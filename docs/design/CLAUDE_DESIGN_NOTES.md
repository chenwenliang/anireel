# Claude design draft — notes

Board: `docs/design/claude-design-board.html` (single self-contained file, inline CSS/SVG, no external assets; open in any browser). It is a competing draft to compare with Sunny's board. Both follow the same rules: `docs/PHASE7_BRIEF.md`, D8/D9 in `docs/DECISIONS.md`.

## Idea in one line
Your feed is the camera roll, and the camera is one tap away from anywhere. The brand gradient is the identity, and the single warm colour (coral) means "do it now".

## Colour roles
- **Mark gradient** (coral #FF6B4A → blue #2F6BFF → violet #8B5CF6): only on the A mark, the centre camera button and primary buttons.
- **Aurora** (cyan #22C1EE → blue → violet): identity surfaces (profile card, empty-state tiles). It never appears on buttons, so the two gradients don't compete.
- **Coral**: record core, selected/active tool states, the used-up quota chip, the sample ribbon.
- Everything else is ink #15131F / #6B6878 on white or #F4F4F8. The mix of cool and warm keeps it gender-neutral for 15–28 without pastel pink.

## Where this draft makes its own choices
1. **Floating capsule tab bar.** A single glass capsule floats over the feed with the camera button docked in its centre, so video runs edge to edge. It's dark glass on the feed and white on the other tabs. *Trade-off:* it covers about 70 pt of the video, so the feed overlays sit above it.
2. **Vertical reel indicator.** Thin segments on the right edge of the feed show your position. They work for both works and samples (1/3, 2/3, 3/3).
3. **Samples look unlike works.** Sample pages have a coral corner ribbon, a glass card and a CTA, plus the line 「示例为风格示意图，实际成片以实时预览为准」. Real works use the minimal Douyin overlay. Nobody should mistake an illustration for their own recording.
4. **Quota is always visible, never a modal until the shutter is pressed.** It's a chip on the feed, a meter on the registration wall, and a stat on the profile card.
5. **Auth uses a 注册 | 登录 segmented control** instead of "already have an account?" links. Labels stay visible while typing, and a strength bar follows the existing letter + number rule.
6. **Forgot password shows a three-step strip** (email → reset on device → done). Step 2 states plainly that no email is sent. With a server backend, step 2 becomes "check inbox".
7. **Result screen adds "next one in another style?" chips.** They lead straight back to the camera with that style selected, to encourage the second (gated) recording right when the user is most excited.
8. **Profile is works-first.** The clip grid sits right under the identity card, and settings/legal shrink to one short list. In this draft, Delete Account is in Settings › Account (one level deeper than the Phase 7 build, which keeps it on 我的). Both satisfy guideline 5.1.1(v); pick one.
9. **Camera rail active state** is a white disc with a coral glyph, which reads on any scene. Plain coloured glyphs vanish on warm scenes.

## Honesty constraints kept
- The registration wall and login state that V1 accounts live only on this iPhone, that no email is sent, and that nothing is tracked.
- The launch screen shows only the mark on indigo, because UILaunchScreen supports one colour and one image.
- The scene art on the board is illustrative SVG, not footage. Store screenshots must use real device captures (docs/APPSTORE.md).

## If this draft is chosen: deltas from the Phase 7 build
- Tab bar: change from the full-width bar to a floating capsule (same items and order).
- Feed: add the reel indicator; move the sample copy into a glass card with the ribbon.
- Auth: add the segmented switch and the forgot-password step strip.
- Result: add the next-style chips (re-uses `ShellState.openCamera(style:)`).
- Profile: add the stats row and an inline 3-column grid (re-uses `ClipThumbnail`).
None of these change RecordingMachine, the gate, ClipLibrary, AuthService or preferences.
