# macOS CI testing package

This fork's `macOS ad-hoc build` workflow creates an Apple Silicon testing package on GitHub's standard `macos-26` runner. The job requires the public fork `xieshiqi147258/DigUp`; a different repository name requires an explicit guard update. It runs on pushes to `main`, `ci/macos-adhoc`, or `fix/chinese-search-isolation`, or manually with `workflow_dispatch` after the workflow exists on the default branch. Each ref has at most one active run, the job times out after 45 minutes, and artifacts expire after seven days. The workflow has only `contents: read` permission and does not persist checkout credentials.

## Build inputs

- Xcode 26.0.1 at `/Applications/Xcode_26.0.1.app/Contents/Developer` (Swift 6.2 or later is required by the manifest). Missing tools fail the job instead of selecting another toolchain.
- llama.cpp `b11461`, checked against commit `4d756bc72bf00a4aacf410ae15a2d315f3db400d`, plus the existing `scripts/llama.cpp-no-logits.patch`.
- Sparkle 2.10.0, checked against commit `eef1a539a373c1f1a320624b1130fc5de7b2e100` from the committed `Package.resolved`. Lockfile drift fails the job.
- Checkout v7.0.1 and upload-artifact v7.0.2, both pinned to full commit hashes. Recursive submodule checkout is enabled; the current source has no submodules.
- CMake is taken from the runner image, checked before building, and its version is recorded. The runner image itself is maintained by GitHub rather than frozen by this workflow.

The workflow builds llama.cpp and the native CLI, runs release-guard checks and `swift test --jobs 2` (including the actual app estimate-helper launch), and invokes the existing `./build.sh` with `SIGN_ID=-` and `RELEASE=0`. It does not invoke `scripts/release.sh`, notarize, create a GitHub Release, update an appcast, or publish to Homebrew. The inherited Homebrew workflow is restricted to the upstream repository and skips in this fork.

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

CI downloads the pinned 310 MB public text model into a temporary folder and verifies its SHA-256. Native tokenizer-budget and limited text-inference tests actually run. The media model is not downloaded, and model weights are not bundled. `ReferenceVectorTests.vectorsMatchTheReference` is disabled by its existing `.enabled(if: modelsThere)` condition because the media model is absent. A green run therefore proves keyword regressions, text-budget tests, the remaining tests and build/package checks passed; it **does not** prove multimodal vector compatibility, UI behavior, semantic-search quality, or full end-to-end operation. The package includes no model weights, indexes, user files, signing identities or notarization credentials. The app can download its model when a person launches it; that download is outside this CI baseline.

## Isolated manual testing

This edition defaults to `~/Library/Application Support/DigUpTest`, uses a dedicated defaults suite and helper identity, refuses original DigUp index paths, and blocks updates in code. Keep this copy in the extracted directory; explicit scratch paths are still convenient for disposable regression runs. Use only synthetic fixtures you created for testing, and do not select personal folders in onboarding or Settings. From the directory containing `package/DigUpTest.app`:

```sh
scratch="$(mktemp -d /tmp/digup-ci.XXXXXX)"
mkdir -p "$scratch/fixtures" "$scratch/index" "$scratch/models"
printf 'A synthetic trip note: take the train to the beach.\n' > "$scratch/fixtures/trip.txt"
open -n "$PWD/package/DigUpTest.app" --args \
  -indexDir "$scratch/index" \
  -modelsDir "$scratch/models" \
  -defaultsSuite "io.github.xieshiqi147258.DigUp.ci.$(basename "$scratch")" \
  -roots "$scratch/fixtures"
```

Automatic and manual update entry points are disabled in this testing edition, including when launched without debug arguments. Existing public Hugging Face cache weights may be copied read-only into its private model directory after validation; the original app's writable model directory is not shared. Broader model-backed validation and any signed fork release require a separate, explicitly chosen scope. No release destination or fork update feed is configured here.
