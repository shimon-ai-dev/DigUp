# macOS CI testing package

This fork's `macOS ad-hoc build` workflow creates an Apple Silicon testing package on GitHub's standard `macos-26` runner. The job requires the public fork `xieshiqi147258/DigUp`; a different repository name requires an explicit guard update. It runs on pushes to `main`, `ci/macos-adhoc`, or `fix/chinese-search-isolation`, or manually with `workflow_dispatch` after the workflow exists on the default branch. Each ref has at most one active run, the job times out after 45 minutes, and artifacts expire after seven days. The workflow has only `contents: read` permission and does not persist checkout credentials.

## Build inputs

- Xcode 26.0.1 at `/Applications/Xcode_26.0.1.app/Contents/Developer` (Swift 6.2 or later is required by the manifest). Missing tools fail the job instead of selecting another toolchain.
- llama.cpp `b11461`, checked against commit `4d756bc72bf00a4aacf410ae15a2d315f3db400d`, plus the existing `scripts/llama.cpp-no-logits.patch`.
- Sparkle 2.10.0, checked against commit `eef1a539a373c1f1a320624b1130fc5de7b2e100` from the committed `Package.resolved`. Lockfile drift fails the job.
- Checkout v7.0.1 and upload-artifact v7.0.2, both pinned to full commit hashes. Recursive submodule checkout is enabled; the current source has no submodules.
- CMake is taken from the runner image, checked before building, and its version is recorded. The runner image itself is maintained by GitHub rather than frozen by this workflow.

The workflow builds llama.cpp and the native CLI, runs release-guard checks and `swift test --jobs 2 --no-parallel` (including the actual app estimate-helper launch), and invokes the existing `./build.sh` with `SIGN_ID=-` and `RELEASE=0`. It does not invoke `scripts/release.sh`, notarize, create a GitHub Release, update an appcast, or publish to Homebrew. The inherited Homebrew workflow is restricted to the upstream repository and skips in this fork.

The complete suite runs serially because the AVFoundation extraction bridge blocks until its asynchronous work
finishes. Concurrent blocking suites plus native model tests can starve Swift Testing's cooperative executor;
per-suite serialization alone does not prevent different suites overlapping. No tests are excluded by this flag.

## Contents and validation

Download the `digup-ci-macos-arm64-<run-id>-<attempt>` Actions artifact and unzip GitHub's outer artifact container. It contains:

- `DigUpTest-ci-macos-arm64-<source-commit>.tar.gz` and its `.sha256` checksum.
- Inside the tar archive: `DigUpTest.app`, the original MIT `LICENSE`, this document as `TESTING.md`, `CHINESE-REGRESSIONS.md`, `STARTUP-PATH-AUDIT.md`, and `BUILD-INFO.txt` with source/dependency revisions, tool versions, and the workflow run URL.
- The app contains its executable, the `digup-test` indexing/query helper with the static llama.cpp runtime, Sparkle and its updater helpers, icons, entitlements/signatures, and third-party `Acknowledgements.txt`.

The app has ad-hoc hardened-runtime signatures and **no Developer ID signature or notarization**. macOS Gatekeeper can block it; a valid `codesign --verify` result does not establish notarization or distribution trust. The app's bundle ID is `io.github.xieshiqi147258.DigUp.ci`, its version is `0.0.0`, automatic update checks are disabled, and its feed is `https://example.invalid/digup-ci/appcast.xml`. Update controls cannot fetch official releases through that feed.

The `.app` travels inside tar because uploading a directory directly does not preserve the executable modes needed to run it. CI extracts the archive, compares every entry's type, permissions and symlink target, checks both executables, and verifies the extracted app's signature. It then generates and checks SHA-256. Verify and extract on a Mac:

```sh
shasum -a 256 --check DigUpTest-ci-macos-arm64-<source-commit>.tar.gz.sha256
mkdir -p package
tar -xzpf DigUpTest-ci-macos-arm64-<source-commit>.tar.gz -C package
codesign --verify --deep --strict --verbose=2 package/DigUpTest.app
```

`digup-ci-logs-<run-id>-<attempt>` is a separate artifact containing available toolchain, llama.cpp build, Swift test, and app build logs, including on failure.

The extracted package also runs `scripts/smoke-test-bundle.py`: normal/code folder estimates and exclusions, pre-model index-service synchronization, Chinese filename retrieval, isolated scratch cleanup, and the real text-worker JSON protocol/inference. See `STARTUP-PATH-AUDIT.md` for the source/method/subprocess/GUI distinctions. The earlier `39930f1` package is superseded because its app-side folder estimator still used the removed helper name; helper status alone did not expose that defect.

## Test coverage limits

CI downloads the exact pinned public text model (310 MB) and media projector (555 MB) into a temporary folder,
verifies both SHA-256 digests, and requires both to be present. The full native suite includes the fixed reference
vector compatibility test, actual tokenizer/inference checks, four genuine public speech-vector replays with eight
English/Chinese queries, six newly inferred no-match queries, mixed-modality assertions and per-input media failure/
retry tests. Required evidence lines make accidental model-test skips fail acceptance. Each native test process has a
bounded timeout and an always-uploaded log; the blocking AVFoundation regression suite is also run in a focused process.

Reference vectors test runtime compatibility, not semantic understanding. The speech reference is synthetic speech-like
audio. Genuine media vectors were produced in the earlier public synthetic-fixture probe and are reused rather than
re-encoding all media. A green result does not prove arbitrary user-library quality, GUI layout, VoiceOver behavior or
full end-to-end operation. See `MEDIA-RECOVERY.md` for provenance, confidence heuristics and limits. The package includes
no model weights, indexes, user files, signing identities or notarization credentials. The app downloads its model when
launched; the isolated on-device download is outside packaging smoke checks.

## Isolated manual testing

This edition defaults to `~/Library/Application Support/DigUpTest`, uses a dedicated defaults suite and helper identity, refuses original DigUp index paths, and blocks updates in code. Keep this copy in the extracted directory; explicit scratch paths are still convenient for disposable regression runs. Use only synthetic fixtures you created for testing, and do not select personal folders in onboarding or Settings. From the directory containing `package/DigUpTest.app`:

```sh
scratch="$(mktemp -d "$HOME/Library/Caches/digup-ci.XXXXXX")"
mkdir -p "$scratch/fixtures" "$scratch/index" "$scratch/models"
printf 'A synthetic trip note: take the train to the beach.\n' > "$scratch/fixtures/trip.txt"
open -n "$PWD/package/DigUpTest.app" --args \
  -indexDir "$scratch/index" \
  -modelsDir "$scratch/models" \
  -defaultsSuite "io.github.xieshiqi147258.DigUp.ci.$(basename "$scratch")" \
  -roots "$scratch/fixtures"
```

Automatic and manual update entry points are disabled in this testing edition, including when launched without debug arguments. Existing public Hugging Face cache weights may be copied read-only into its private model directory after validation; the original app's writable model directory is not shared. Broader model-backed validation and any signed fork release require a separate, explicitly chosen scope. No release destination or fork update feed is configured here.


## UI localization gates

The app uses a tiny `DigUpLocalizationResources` resource-only target. This keeps SwiftPM's generated `Bundle.module` accessor outside the UI target's default MainActor isolation. The packaged bundle is `DigUp_DigUpLocalizationResources.bundle`; `build.sh` checks the exact generated accessor and copies the entire bundle before signing.

`python3 scripts/check-localization.py` validates the English/Simplified Chinese key sets, reviewed UI-key inventory, placeholder positions/types and the supported `n` plural schema. Only English one/other and Simplified Chinese other are implemented; additional languages need explicit plural-rule work, not just another translation file.

The archive job runs `scripts/smoke-test-localization.py` against the extracted app. It copies the app outside the checkout, temporarily hides `.build` with guaranteed restoration on ordinary failure/termination, and tests English, Simplified Chinese and unsupported-language fallback. It checks all five bundled permission purpose strings and confirms deleting the nested resource bundle fails closed. This read-only CLI probe exits before the GUI, settings, helper or downloads start.

A separate `scripts/smoke-test-app-startup.py` gate launches the extracted, signature-verified app
through its real `NSApplication.run` and `applicationDidFinishLaunching` path. It checks the
same-bundle default domain, an explicit same-bundle domain, and a separate custom development
suite, including pre-existing test preferences. It requires the engine searcher to become ready,
delayed main-loop menu callbacks and a clean timed shutdown. The explicit same-bundle case also
constructs and renders the welcome window to PNG. All source/index/model paths are disposable;
no folders are selected, no model download is started, and original DigUp data/settings metadata
must remain unchanged. Empty onboarding/code locations prevent home-folder estimates. This is
a bounded offscreen AppKit startup regression, not an on-screen usability, Gatekeeper, privacy
permission, hotkey, login-item or full end-to-end test.

See `UI-LOCALIZATION.md` for the manual acceptance checklist. CI does not prove layout, VoiceOver or actual macOS permission dialog presentation. The inherited source-folder alias limitation remains unchanged.
