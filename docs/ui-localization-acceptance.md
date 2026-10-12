# DigUp Test UI localization acceptance

## Scope and test identity

This change adds English and Simplified Chinese UI resources, selected by macOS app language preferences on launch, with an English per-key fallback. It does not add a language picker or change the search index, tokenization, IME behavior, source-folder alias handling, or model.

The testing app remains `DigUpTest.app`, bundle ID `io.github.xieshiqi147258.DigUp.ci`, helper `digup-test`, and separate settings/index/models/temp directories. It is ad-hoc signed, not Apple notarized. Do not replace the original DigUp application or use its data folders.

## Evidence levels

Resource validation and unit tests prove key/placeholder matching, language selection, fallback, typed status formatting and stable menu identities. Packaged command-line smoke tests prove the relocated app can read its own resources, without a developer checkout, and fails when those resources are missing. These do not prove UI layout, VoiceOver behavior or macOS privacy dialogs.

A successful model inference test is not a complete media search quality evaluation. The media model is not downloaded by this workflow; existing model-dependent skips remain skips.

## Manual acceptance (not yet verified)

Run both English and Simplified Chinese, then change macOS per-app language and fully quit/relaunch.

- Menu bar menu and app menu: all titles, pause/resume, keyboard equivalents, settings, quit.
- Search window and compact panel: placeholders, empty/code-off states, examples, filters, strong/weaker results, preview toggles.
- Use a synthetic filename `100%「合同」.md` and long mixed-language paths. Filename, path, excerpt and code remain verbatim.
- Results: PDF pages, code lines/cells, audio/video timecodes, open-at-moment and play-at-moment hints.
- Settings: each tab, folder add/remove/cancel, code enable/disable confirmation, storage paths and index details.
- First-run onboarding: each step; 680×600 and narrower fixed sheets; long descriptions, multiline labels, buttons not truncated.
- VoiceOver: search field, shortcut recorder, result names/reasons, timeline, onboarding progress, folder disclosure controls.
- Permissions: allow, deny and restore folder access; inspect the real system prompt and requesting app/helper identity. Bundled translated purpose strings alone do not prove the system displayed them.
- Download and indexing: failure/retry, low power, battery, warm device, paused and pending files; no omitted numbers or reasons.
- Unsupported language: English fallback. Changing region independently preserves selected UI language while numeric formatting follows region.
- Original DigUp: verify it still has separate defaults/index/models and is unaffected by the test app.

No item above has been marked passed through access to the user's Mac. Such access requires a separate explicit authorization.
