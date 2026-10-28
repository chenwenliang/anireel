# Phase 6 Brief — Launch-completeness gap fill (Sunny gap analysis, 2026-10-29)

User instruction: "其它需要的功能，你自行分析并补齐" — Sunny analysed the gap between the current build and a launch-ready style-camera app. Execute AFTER Phase 5. All UI zh/en. No networking, no third-party SDKs.

## A. Account deletion + Settings (App Store hard requirement)
- Phase 5 adds account creation, so App Store Review Guideline 5.1.1(v) REQUIRES in-app account deletion. Add to the account area: "Delete account" with a confirmation flow (re-enter password), deleting the local account, its Keychain entries and session; the user returns to guest state (guest free-recording rule applies as for a fresh guest — document the choice in PROGRESS.md).
- Settings screen (reachable from main screen): account section (state, sign out, delete account), capture defaults (default camera position, front mirroring default, mute-by-default), storage section (local library size, clear library), about section (version, Privacy Policy, Terms of Service — opens the in-app legal pages from item E), feedback (mailto link placeholder).

## B. Post-recording result screen
- After a clip is saved, show a result screen: loop playback of the just-recorded stylized clip, with actions: Share (system share sheet), Retake (back to camera, same style), Done (back to main). Auto-save behaviour from Phase 2 stays; the result screen is the confirmation surface (replace the transient toast as the primary confirmation; keep behaviour consistent with the RecordingMachine states and do not break its tests).

## C. My Clips (local library)
- Every successfully saved clip is also kept in an app-local library (sandbox) with metadata (date, duration, style id). My Clips screen: grid of thumbnails, tap to play, share, delete (deleting local copy only; explain it does not remove the Photos copy). Empty state for no clips. Guests and registered users both get the library (it is on-device data).
- Storage guard: show total size in Settings (item A); no silent cap in V1, document in PROGRESS.md.

## D. Share
- System share sheet (UIActivityViewController) for a clip file, used by the result screen and My Clips.

## E. Legal pages (in-app)
- Privacy Policy and Terms of Service as in-app readable pages, zh/en, text consistent with the app (on-device processing, local accounts in V1, no tracking). Store the text as bundled resources. Note in docs/APPSTORE.md that the store listing still needs a hosted privacy-policy URL before submission (pre-launch item for the user).

## F. First-launch onboarding + style extensibility surface
- 3-page first-launch onboarding (what the app does, the three styles, "first recording is free, no account needed"), skippable, shown once; then permissions are requested in context as today (do not request camera/mic on the onboarding pages).
- Style picker gains a disabled "More styles coming soon" cell, demonstrating the style-pack extension point to users.

## G. Small capture features (cheap, expected in this category)
- 3-second self-timer option for starting a recording.
- Back-camera torch toggle (only when the device has a torch; hidden/disabled on front camera and in the demo source).
- Grid overlay toggle (rule-of-thirds lines on the preview only, never in the recorded file).
- Press-and-hold on the preview to peek at the unstyled original frame; release returns to the styled view (preview only, recording unaffected if pressed while recording — if risky, disable during recording and note it).

## Tests & docs
- Unit tests for new pure logic: account-deletion state effects, library metadata store, timer/gate interplay if any (the Phase 5 gate must still count only saved clips).
- Update PROGRESS.md (with every decision you had to make and its reason), README.md, docs/APPSTORE.md checklist. Then stop.
