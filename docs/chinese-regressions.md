# First Chinese regression batch

This testing edition improves exact keyword retrieval and complete document inputs. It does not change the model weights or claim that semantic understanding became stronger. UI language resources are a separate future batch.

## Reproduced before the fixes

The regression-only commit `8975f60` on `fix/chinese-search-isolation` ran on standard macos-26/Xcode 26.0.1. [Run 38214279420](https://github.com/xieshiqi147258/DigUp/actions/runs/38214279420) compiled successfully and failed functional assertions for Han keywords/filename interiors, phrase highlighting/page landmarks, no-space overlap, PDF tail embedding, schema5 keyword migration and the original model directory. Its public synthetic keyword-only corpus reported R@1 **1/10**.

After the keyword/filename/migration commit `7ca48a7`, [run 38214966209](https://github.com/xieshiqi147258/DigUp/actions/runs/38214966209) reported **10/10** on the identical corpus. It downloaded and hash-verified the pinned public text model; the native overflow regression failed because a too-long input returned a vector after silent truncation. Remaining expected failures still covered PDF tail, overlap and data isolation. Full final verification is recorded in the subsequent successful workflow run associated with the delivered package's BUILD-INFO.txt.

## Changes

- Index and query use the same Han-character representation. Queries use contiguous FTS phrases, so two-character terms such as 租房 and 合同 match inside longer runs without becoming unrelated-character OR searches. Original strings are preserved for excerpts and page landmarks. Existing English stemming and Bengali/Arabic normalization remain.
- Filename substring fallback uses a separate SQLite trigram index for terms of at least three characters, restricted to filenames and bounded to 100 candidates per term. Two-character Han queries use the main phrase index. It neither scans folder/body strings for arbitrary substrings nor uses an unindexed LIKE fallback; rename/deletion and kind filters have regressions.
- Schema6 rebuilds keyword text from stored originals and builds the filename index. Previously indexed long passages that may contain truncated vectors, plus garbled PDF text vectors whose original length is unavailable, are queued for re-extraction. Only already indexed files under the user's existing chosen roots are eligible; migration itself does not read source files or expand roots. The test edition never opens the original app's index.
- No-space Han document chunks retain overlap. PDF vector inputs use the complete page text instead of prefix(4000), with multiple parts carrying the same original page number. Coarse document continuation positions remain stable even when a passage is subdivided.
- Native llama.cpp and the optional reference worker expose actual tokenizer counts. Splitting includes document title, prompt and special tokens, rechecks every emitted piece, retains overlap and the tail, and fails clearly if the title leaves no space. Direct oversized embeddings throw instead of silently truncating. The generic byte-bound fallback is only for simple/test embedders; production runtimes provide token counts.
- DigUpTest.app, its DigUpTest executable and digup-test helper have independent identities. Indexes, models and settings default to the testing namespace. Original-index aliases are rejected; original data-directory overrides are not adopted by app settings. Update entry points are disabled and the signed bundle uses an invalid feed.

## Validation scope

The public synthetic lexical corpus uses **no query vectors** and measures exact-keyword R@1, not semantic-search quality. Budget tests include title overhead, overlap, complete tail coverage, tiny English/Bengali/Arabic passages, an impossible budget and original-index protection. The native test uses real public text weights, checks complete synthetic numbered records against the tokenizer, and validates two finite inference vectors.

`ReferenceVectorTests` still skips without the media weights; no multimodal/vector-compatibility pass is claimed. The optional Python/MLX reference worker is syntax-checked but its model inference is not exercised by this native CI. Archive permission/symlink/signature/checksum and helper identity/default path checks run before artifact upload. There is no desktop UI acceptance test or user-data corpus in this batch. The delivered app is ad-hoc signed and not notarized.
