# macOS CI testing package

This fork's `macOS ad-hoc build` workflow creates an Apple Silicon testing package on GitHub's standard `macos-26` runner. The job requires the public fork `xieshiqi147258/DigUp`; a different repository name requires an explicit guard update. It runs on pushes to `main` or `ci/macos-adhoc`, or manually with `workflow_dispatch` after the workflow exists on the default branch. Each ref has at most one active run, the job times out after 45 minutes, and artifacts expire after seven days. The workflow has only `contents: read` permission and does not persist checkout credentials.

## Build inputs

- Xcode 26.0.1 at `/Applications/Xcode_26.0.1.app/Contents/Developer` (Swift 6.2 or later is required by the manifest). Missing tools fail the job instead of selecting another toolchain.
- llama.cpp `b11461`, checked against commit `4d756bc72bf00a4aacf410ae15a2d315f3db400d`, plus the existing `scripts/llama.cpp-no-logits.patch`.
- Sparkle 2.10.0, checked against commit `eef1a539a373c1f1a320624b1130fc5de7b2e100` from the committed `Package.resolved`. Lockfile drift fails the job.
- Checkout v7.0.1 and upload-artifact v7.0.2, both pinned to full commit hashes. Recursive submodule checkout is enabled; the current source has no submodules.
- CMake is taken from the runner image, checked before building, and its version is recorded. The runner image itself is maintained by GitHub rather than frozen by this workflow.

The workflow builds llama.cpp, runs `swift test --jobs 2`, and invokes the existing `./build.sh` with `SIGN_ID=-` and `RELEASE=0`. It does not invoke `scripts/release.sh`, notarize, create a GitHub Release, update an appcast, or publish to Homebrew. The inherited Homebrew workflow is restricted to the upstream repository and skips in this fork.

## Contents and validation

Download the `digup-ci-macos-arm64-<run-id>-<attempt>` Actions artifact and unzip GitHub's outer artifact container. It contains:

- `DigUp-ci-macos-arm64-<source-commit>.tar.gz` and its `.sha256` checksum.
- Inside the tar archive: `DigUp.app`, the original MIT `LICENSE`, this document as `TESTING.md`, and `BUILD-INFO.txt` with source/dependency revisions, tool versions, and the workflow run URL.
- The app contains its executable, the `digup` indexing/query helper with the static llama.cpp runtime, Sparkle and its updater helpers, icons, entitlements/signatures, and third-party `Acknowledgements.txt`.

The app has ad-hoc hardened-runtime signatures and **no Developer ID signature or notarization**. macOS Gatekeeper can block it; a valid `codesign --verify` result does not establish notarization or distribution trust. The app's bundle ID is `io.github.xieshiqi147258.DigUp.ci`, its version is `0.0.0`, automatic update checks are disabled, and its feed is `https://example.invalid/digup-ci/appcast.xml`. Update controls cannot fetch official releases through that feed.

The `.app` travels inside tar because uploading a directory directly does not preserve the executable modes needed to run it. CI extracts the archive, compares every entry's type, permissions and symlink target, checks both executables, and verifies the extracted app's signature. It then generates and checks SHA-256. Verify and extract on a Mac:

```sh
shasum -a 256 --check DigUp-ci-macos-arm64-<source-commit>.tar.gz.sha256
mkdir -p package
tar -xzpf DigUp-ci-macos-arm64-<source-commit>.tar.gz -C package
codesign --verify --deep --strict --verbose=2 package/DigUp.app
```

`digup-ci-logs-<run-id>-<attempt>` is a separate artifact containing available toolchain, llama.cpp build, Swift test, and app build logs, including on failure.

## Test coverage limits

CI sets `DIGUP_MODELS` to an empty temporary folder and never downloads model weights. `ReferenceVectorTests.vectorsMatchTheReference` is disabled by its existing `.enabled(if: modelsThere)` condition. A green baseline run therefore proves the remaining tests and build/package checks passed; it **does not** prove vector compatibility, actual model inference, UI behavior, semantic-search quality, or full end-to-end operation. The package includes no model weights, indexes, user files, signing identities or notarization credentials. The app can download its model when a person launches it; that download is outside this CI baseline.

## Isolated manual testing

A separate bundle ID alone does not isolate the app's default `~/Library/Application Support/DigUp` index and models paths. Keep this copy in the extracted directory and launch it with explicit scratch paths and a separate defaults suite. Use only synthetic fixtures you created for testing, and do not select personal folders in onboarding or Settings. From the directory containing `package/DigUp.app`:

```sh
scratch="$(mktemp -d /tmp/digup-ci.XXXXXX)"
mkdir -p "$scratch/fixtures" "$scratch/index" "$scratch/models"
printf 'A synthetic trip note: take the train to the beach.\n' > "$scratch/fixtures/trip.txt"
open -n "$PWD/package/DigUp.app" --args \
  -indexDir "$scratch/index" \
  -modelsDir "$scratch/models" \
  -defaultsSuite "io.github.xieshiqi147258.DigUp.ci.$(basename "$scratch")" \
  -roots "$scratch/fixtures"
```

The defaults-suite argument also suppresses the updater in existing app code. Model-backed validation and any signed fork release require a separate, explicitly chosen scope. No release destination or fork update feed is configured here.
