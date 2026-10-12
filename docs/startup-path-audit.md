# Testing-edition startup path audit

This checklist distinguishes source review, automated process tests, and remaining GUI acceptance. A green workflow is not a complete desktop acceptance test. The exact tested commit and workflow are in the package's BUILD-INFO.txt.

## Reviewed entry points and automated checks

- **Onboarding and Settings folder estimates:** `FolderChoices` calls `Estimates.run`. It now shares `AppIdentity.bundledHelper` with both Engine launch sites. `EstimateHelperTests` invokes the actual app method with the real freshly built CLI installed only under `digup-test` at the test runner’s bundle location on the disposable CI runner, requires a real document-count callback, and separately requires an explicit failed callback when the helper is absent. This tests the method and subprocess boundary, not clicking the onboarding screens.
- **Indexing service:** Engine uses the same bundled-helper resolver. The extracted-package smoke launches `index-service` on public synthetic folders before model availability, requires sync/waiting/exit events, checks the isolated index, and retrieves the Chinese filename through the actual CLI. It probes Foundation’s actual temporary directory and exclusively creates synthetic original/test scratch sentinels there, refusing to adopt existing directories. Original-prefixed scratch must survive while stale testing scratch is removed. The Python harness cleans only its owned sentinels; the helper’s production cleanup also sweeps stale DigUpTest-prefixed folders. This smoke is restricted to the disposable GitHub CI runner. This does not exercise full document/media embedding or the GUI's indexing state machine.
- **Query worker:** Engine's native worker configuration uses the same resolver. The extracted-package smoke starts `worker --text-only` using pinned public text weights, checks ready/token_count/text/quit messages and two finite, nonzero 768-dimensional vectors. GUI keystrokes, cancellation, idle unloading, and result interaction still need desktop acceptance.
- **Helper estimates and options:** The extracted executable estimates synthetic regular folders and code folders, including folder and extension exclusions. The package must contain an executable `digup-test` and must not contain a `digup` compatibility alias.
- **App identity and data:** The test bundle, helper signature, settings domain, default index/model paths, scratch prefix, and debug pasteboard use testing identities. Data-alias tests cover original paths, dangling and relative symlinks, safe macOS temporary paths, cycles, and fail-closed app defaults. These checks do not grant access to or copy a user's original index.
- **Updates and publishing:** Automatic/manual updater entry points are disabled in source; the extracted plist must contain the testing bundle ID, disabled checks and an invalid feed. Inherited release/appcast scripts explicitly reject testing source/bundle identities before signing or writing a feed. A local fixture regression checks these guards and that the inherited release implementation remains behind the guard (the original identity reaches its existing credential precondition, not a validated signed release). CI neither signs a Developer ID release nor publishes an appcast.
- **Other process launches:** Source review classified editor launch, git discovery and AppleScript/QuickTime interactions separately from the bundled helper. Their runtime behavior was not covered by these helper smoke tests.

## Package checks

CI verifies ad-hoc signatures before and after archive extraction, compares entry modes and symlinks, executes the extracted helper, and verifies the tar SHA-256 before upload. The downloaded artifact and inner tar checksums are verified again before delivery. No weights, index or user files are bundled.

## Still requires explicit desktop acceptance

No full GUI onboarding, Gatekeeper first-open flow, macOS privacy prompts, hotkeys, login items, full media-backed indexing, or real user corpus has been tested. The media model is absent in CI, so ReferenceVectorTests remains skipped. Synthetic keyword results and limited text inference are not evidence of improved semantic-search quality. The package is ad-hoc signed and not notarized.

### Known source-root path limitation

The inherited index-service scope uses a chosen root's spelling while the crawler can return its physical spelling. Under macOS `/var` versus `/private/var`, this can produce empty scoped counts. Source-root normalization is not changed in this batch. CI and the manual instructions therefore place synthetic source fixtures in an ordinary `~/Library/Caches` directory; the scratch-isolation test still uses Foundation's actual temporary directory. Do not treat these checks as validation of every source-root alias.
