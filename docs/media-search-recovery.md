# Bounded media search recovery

This DigUpTest change keeps the existing relevance gate and qualifying result order. Audio, video, screenshots and
photos that miss the default statistical gate may appear in a separate, folded low-confidence suggestion tier.
Suggestions are heuristic candidates, not calibrated probabilities or proof that the model understood the query.
At the default zGate=2.0, recovery requires cosine at least 0.65 and, when same-modality peers exist, a margin of at
least 0.04 over their mean. At most three are appended. Explicit --zgate values remain exact diagnostic controls;
code and text-only results have no recovery tier. Invalid/zero/non-unit vectors are excluded from scoring.

## Evidence and reproducibility

`Tests/LlamaRuntimeTests/MediaRecovery/public-audio-vectors.json` contains four full-model media vectors and eight
English/Simplified Chinese query vectors from public, locally generated macOS Samantha speech. The neutral filenames
are f001–f004; the topics are groceries, delayed flights, quarterly revenue and chocolate cake. Original evidence:

- [Public source run 38253464125](https://github.com/xieshiqi147258/DigUp/actions/runs/38253464125)
- Artifact `digup-media-probe-38253464125-1`; four-clip SQLite snapshot and `core-four-query-vectors.stdout.log`
- Model revision bfcd298762cc34d0357ece5ebdd31791a3a374d8; llama.cpp b11461, vectors1
- Text model SHA-256 2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135
- Media model SHA-256 c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f

Six new no-match query maxima measured 0.4926–0.5798; the positive maxima were 0.7294–0.8220.
The 0.65 floor was chosen conservatively between these observed groups; it is not a general relevance guarantee.

All eight expected answers were raw top-1 among the four real speech clips. All eight were hidden by the old default
zGate=2.0. A group of four scores cannot reach a population z-score of 2; the best possible value is sqrt(3).
The replay uses the actual production Searcher and preserved vectors, including the float16 storage conversion.
It does not repeat media inference, and it does not claim new model understanding.

The acceptance suite also infers six new no-match queries with the pinned text model (EN/ZH lunar geology, violin
orchestras and bicycle tires), prints their actual cosines against all four recordings and checks default All and
audio-only searches. A mixed text/image/audio replay exercises cross-modality normalization. Synthetic tests cover
invalid vectors, low signal, near-equal scores, suggestion limits, explicit diagnostic gates and existing result order.

`public-multimodal-vectors.json` also preserves the exact single-query vectors, 22 real text distractors and media
segments from [run 38257779846](https://github.com/xieshiqi147258/DigUp/actions/runs/38257779846), artifact
`digup-media-probe-38257779846-1`, using the same pinned model revision and hashes above. Its replay checks the prior
10 strong English/Chinese photo, Chinese screenshot, video frame/sound and late-audio answers and locations unchanged,
in explicit-kind and All searches. The late-audio match remains 75–90 seconds. The Chinese spoken-content query's
cosine 0.652768 is exposed only as a low-confidence suggestion; its English counterpart at 0.593672 remains below the
floor. Those two queries still have only one audio candidate, so this is compatibility/labeling evidence, not proof
of Chinese speech discrimination. Stored segments retain exact float16 bytes; queries retain exact single-query
float32 bytes, avoiding the measured batch-versus-single encoding variance.

## Indexing failures and retry

Audio/video responses are checked per input for errors, missing vectors, invalid vectors and response-count mismatch.
Successfully embedded windows/frames remain searchable. An incompletely embedded file stays failed and retains the
original error plus the media location. One retry is allowed on the next sync for unchanged media encoding failures;
subsequent automatic syncs do not loop forever. Retrying reuses successful locations and adds only missing segments.
An explicit retry can be requested from Settings or with the developer CLI's --retry-failed option.

Unchanged legacy audio/video incorrectly marked done is checked for deterministic signs: nil or wrong-sized
audio/frame vectors, done audio with no audio rows (unless an explicit zero count was stored), and missing rows
against declared frame/sound-window counts. These become visible failures without starting automatic repair.
Settings shows a localized earlier-version explanation; explicitly choosing Retry fills only missing locations and
keeps successful segments. The reconciliation is idempotent, applies only to connected selected folders, and does
not run on the code index or original DigUp data. Healthy media and explicitly skipped/zero-count silent media are
left alone. Audio duration is never used to guess missing windows because silence/short tails may be omitted.

## Limits

The cosine and contrast gates are empirical safeguards. No-match controls cover a small public corpus, not every
possible irrelevant query or user library. A lower-confidence suggestion can still be wrong. Chinese queries about
English speech and Chinese spoken-content retrieval are different tests; results from the former do not validate the
latter. The original Chinese-spoken-content probe had only one audio candidate and does not establish discrimination.
Partial legacy audio with some valid rows but no stored expected-window count may be indistinguishable from omitted
silence. The old encoder error cannot be recovered if the previous version never stored it; the repair records the
missing-vector/count evidence rather than inventing an error. No full index rebuild is required for diagnosed cases.

Full reference-vector tests check compatibility with fixed input vectors, not semantic quality. The original reference
speech fixture is synthetic speech-like audio. The app remains ad-hoc signed, unnotarized and isolated as DigUpTest;
model weights are temporary test inputs and are not included in the installation package. Actual GUI layout,
VoiceOver behavior and private user files remain outside automated verification.
