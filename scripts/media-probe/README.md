# Throwaway multilingual media diagnostic

This opt-in probe answers whether the **current pinned model and unchanged application pipeline** retrieve the actual content of neutral-named media from English and Chinese synonymous queries. It does not change application behavior, retune gates, replace a model, or publish an app. Semantic misses are observations, not infrastructure-test failures.

## Reproduce on an authorized Apple Silicon macOS machine

Use a fresh output directory under **`$HOME/Library/Caches`, outside a repository**, because DigUp deliberately excludes most media inside code projects. This also avoids the macOS `/var` versus `/private/var` path-alias mismatch in source scopes. Set `DIGUP_MODELS` to the directory containing the exact files in `Sources/DigUpKit/ModelFiles.swift`, after verifying their byte sizes and SHA-256 hashes. The CI workflow performs this verification before running the probe.

```sh
scripts/build-llama.sh
swift build --jobs 2 --product digup
swiftc -parse-as-library scripts/media-probe/render_fixtures.swift -o /tmp/digup-media-renderer
python3 scripts/media-probe/test_probe.py
python3 scripts/media-probe/make_fixtures.py \
  --output "$HOME/Library/Caches/DigUpTest-media-probe" --renderer /tmp/digup-media-renderer
unset DIGUP_WORKER_DIR
python3 scripts/media-probe/run_probe.py \
  --cli "$(swift build --show-bin-path)/digup" --output "$HOME/Library/Caches/DigUpTest-media-probe"
```

The separate `.github/workflows/media-probe.yml` runs only on `ci/chinese-media-probe` or a manual dispatch. It is restricted to the authorized public fork `xieshiqi147258/DigUp`, uses standard `macos-26`, and has a 45-minute job limit. Existing app packaging is not triggered by that branch. No model files, private user files, or indexes are uploaded; generated public fixtures and diagnostic reports/logs are the only artifacts.

## Fixtures and honest coverage

- Required intelligible English Samantha TTS: shopping for milk/eggs, storm flight delay, 20% quarterly revenue growth, and chocolate cake. Sixteen different spoken distractors supply interference.
- A 90-second recording contains only gardening speech during seconds 0–65, then vanilla frosting/strawberry speech during seconds 65–90. Localization requires an audio segment starting at 50 seconds or later and extending past 65 seconds; the 30-second/25-second-hop window can legitimately start before the target.
- `say -v '?'` inventories installed voices. Chinese speech is attempted only when a `zh_CN` voice is listed; no voice is installed. Unavailable/failed Chinese synthesis is labeled UNTESTED. English and Chinese queries still search the same English audio.
- Locally rendered English airport and Chinese revenue screenshots contain readable text, unlike the synthetic rectangles in the existing reference-vector fixture. The actual index's Apple Vision OCR text is recorded.
- Short English shopping and Chinese cake text files exercise both semantic and lexical content search.
- If available, `/Library/User Pictures/Animals` supplies documented macOS-bundled ordinary photographs. Neutral destination names prevent the source filename from answering the query. Missing pictures are UNTESTED.
- Locally generated MP4 has a still frame and a distinct English flight soundtrack. Both frame and sound queries are checked with expected segment types. A Chinese screenshot is the fallback frame when ordinary photographs are unavailable.
- Deterministic synthetic rain-like noise and a repeated macOS Glass alert exercise environmental/audio input paths. They cannot establish quality on recordings of real weather or arbitrary real-world sounds.

All filenames and indexed directory names are neutral IDs. Source transcripts, topics, voice inventory, and image provenance remain in `manifest.json` **outside `inputs/`**, so they cannot accidentally rescue audio through keyword search. Actual generated media is included in the CI artifact for listening and visual inspection.

## Observations and stopping condition

`run_probe.py` uses the actual CLI `index`, `worker --text-only`, and `search`, not injected reference vectors. Audio indexing and its paired query results are saved first, before adding other modalities. Each command has a timeout; every completed phase and query is checkpointed atomically to `results.json`. Failure does not erase completed audio observations.

The report separates:

- Real indexed file states, segment types, timestamps, vector presence/size/finiteness/norm, OCR, and counts per modality
- Worker-generated query vectors and raw segment cosine rankings from the real SQLite float16 vectors
- Diagnostic z values reproduced from `Searcher.meaning`, cross-checked against actual CLI cosine/z within 0.001/0.01
- Authoritative wide-candidate CLI search (`--zgate -1000000 --word-weight 0`), unchanged default search, and keyword-candidate-only search (`--zgate 1000000`). That last mode prevents semantic-only admission but still uses computed semantic weights when ranking keyword candidates
- Raw file rank, wide rank, default rank, keyword-candidate rank, each hit’s FTS keyword rank, score, z, cosine, chosen segment, `loc`, `loc_end`, excerpts, and observed top-1/top-5 quality for every query
- Identical core queries on audio-only and mixed/interference corpora
- Isolated database copies retaining exactly 1, 2, 3, and 4 real short-audio vectors. These demonstrate whether the default z=2 gate suppresses even the best content match. No synthetic vectors are inserted.

Raw cosine rank is **not** assumed to equal wide fused rank: production search centers modalities, clamps negative z contributions, applies kind hints, and collapses each file to one chosen segment. CLI results are authoritative. Only short document fixtures are used, so there are no later long-document vectors excluded from the normalization scale.

The run ends when all available fixture cases and small-sample comparisons have been recorded, or on an infrastructure blocker/timeout. Missing required English topics, invalid/missing vectors for generated fixtures, worker failure, and disagreement between diagnostic math and the CLI fail the infrastructure run. Semantic retrieval/localization failures remain explicit `FAIL` rows in an otherwise `COMPLETED` diagnostic, never disguised as passing quality tests. Optional unavailable sources remain `UNTESTED`.

The known behavior where audio/video indexing can mark a file done after an individual embedding returned no vector is **not fixed**. The segment audit detects nil/invalid vectors even when the file state says done. The indexer may discard the original per-embedding error; report the missing vector rather than inventing its cause.

## Local verification limits

`test_probe.py` is a stdlib-only mathematical/report contract test, not native media inference. Linux can run those checks and parse Python/workflow shell syntax. Native Swift compilation, Apple speech/OCR/AVFoundation, pinned-model inference, and actual retrieval quality require the macOS CI run. The existing reference-vector WAV contains generated syllables and is not used as evidence of semantic speech recognition.
