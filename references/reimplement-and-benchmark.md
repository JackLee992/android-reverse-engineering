# Re-implementing decompiled logic into a fresh app + honest on-device benchmark

Use when the goal isn't just to document an APK, but to **rebuild its logic in a
new app** (often combining it with a second source, e.g. a server codebase) and
then **quantify a real metric on-device** (pass rate, per-frame latency). This is
Phase 8 territory: after decompile/analyze, port → validate → benchmark.

## Core discipline: de-risk with a byte-parity spike BEFORE building the app

Do not scaffold a whole Android/Gradle project first. The expensive risk is
"does my re-implementation produce identical bytes to the reference?" Answer it
cheaply on the desktop JVM:

1. Port the pure-logic classes (crypto, codecs, parsers) to plain Java, no
   Android deps. Compile standalone with `javac -cp <libs>`.
2. Get a **ground-truth** run from the authoritative reference (e.g. the server's
   Python pipeline) that emits per-item hashes: fragment SHA-1s, decrypted-text
   SHA-1, output lengths.
3. Run the JVM port on the SAME inputs and assert the hashes match **byte-for-byte**.
   Only after parity holds do you build the app around the ported classes.
4. Reuse the identical `.java` in both the JVM harness and the app (copy +
   `sed 's/^package .../package .../'`). Keeping them literally the same file
   (diff modulo package line == IDENTICAL) means the fast desktop full-set run
   genuinely validates the app's algorithm — you cross-check the phone against it.

Powerful invariant to look for: if `decode_ok == decrypt_ok` on every item, the
downstream stage (decrypt/parse) is proven correct and the pass rate is gated
entirely by the upstream stage (decode). State this explicitly; it tells you
where the only lever is.

## Fidelity口径: "app-faithful" vs "enhanced" — measure both, never conflate

When the ask is "reuse the app's logic," replicate the decompiled decode config
EXACTLY (same library, same `LuminanceSource`/binarizer/hints, same full-frame
no-crop) and report that number as the faithful baseline. Do NOT chase a
different reference's number (e.g. a server using a different engine + heavier
preprocessing) — engines differ (ZXing-Java vs zxing-cpp gave a 7x gap here on
identical input). If you then add enhancements, gate them behind a flag and
report baseline-vs-enhanced as separate rows with the latency cost of each.

## On-device instrumented benchmark harness (androidTest)

Pattern that works: an `androidx.test` `@Test` that walks a sample dir, runs the
pipeline per image, and writes `result.csv` + `summary.txt` (pass rate, p50/p90/p99
latency, per-stage timing, and a "which enhancement stage hit" distribution).
Drive it with `am instrument -e <key> <val>` args:
```
adb shell am instrument -w -e samplesRoot /sdcard/ine_samples -e limit 0 \
  -e cascade true <pkg>.test/androidx.test.runner.AndroidJUnitRunner
```
Warm up 3 iterations before timing so JIT/class-load isn't a first-sample outlier.
Measure decode-only and end-to-end separately.

### Android 12+ scoped-storage gotchas (these are FIXES, not "storage is broken")
- The instrumented app process **cannot traverse arbitrary `/sdcard/...`** by
  default. Fix: add `READ_EXTERNAL_STORAGE` + `MANAGE_EXTERNAL_STORAGE` +
  `android:requestLegacyExternalStorage="true"`, then grant at runtime:
  `adb shell appops set <pkg> MANAGE_EXTERNAL_STORAGE allow`. Samples pushed to
  `/sdcard/ine_samples` are then readable.
- Writing results to another app's external dir yields files with mode 0600 that
  `adb pull` can't read ("remote open failed: Permission denied"). Fix: write
  results to **internal** storage (`context.getFilesDir()`) and retrieve with
  `adb exec-out run-as <pkg> cat files/ine_bench/summary.txt` (works because the
  debug build is debuggable). `run-as` only reaches internal storage.
- Pushing directly into `/sdcard/Android/data/<pkg>/files/` is flaky over adb on
  some OEM devices ("failed to read copy response") — push to plain `/sdcard/...`
  and read via the MANAGE_EXTERNAL_STORAGE grant instead.
- Avoid non-ASCII sample filenames over adb; stage to ASCII names (`<id>_back.jpg`)
  and make the on-device walker accept both patterns.

## Image-preprocessing cascade, pure-Java (no OpenCV dep keeps the app light)
- Implementable in plain Java: grayscale (BT.601), bilinear upscale, separable
  Gaussian (σ=1, 7-tap), unsharp = `2.5*src - 1.5*gauss`, CLAHE (clipLimit=3,
  8×8 tiles, bilinear LUT interp). Order variants by marginal gain, run
  **stop-on-hit**: only failing frames pay the cost (p50 jumps from ~5ms to
  hundreds of ms only on the failure population).
- **OOM cap**: guard every upscale with a max-pixel ceiling
  (`(long)w*f*h*f > MAX_UPSCALE_PIXELS → skip`). A pathological large still
  (e.g. 37MP ×4 ≈ 593M px) otherwise triggers `OutOfMemoryError` on a ~128MB
  allocation. Also set `android:largeHeap="true"`. Mirror the identical cap in the
  JVM harness so both口径 stay in lockstep.

## Toolchain / China-network build notes
- AGP pins an exact build-tools revision and tries to auto-download it if absent
  (blocked offline) → set `buildToolsVersion = "<installed>"` explicitly.
- `--offline` fails on first build (deps not cached); build online once.
- Stale empty proxy in `~/.gradle/gradle.properties` breaks resolution — override
  per-project (`systemProp.http.proxyHost=`) and use aliyun mirrors in
  `settings.gradle.kts` (`maven.aliyun.com/repository/{google,public,gradle-plugin}`).
- Generate the wrapper from a cached gradle: `<cached>/bin/gradle wrapper --gradle-version X`.

## Comparing your rate against a reference's headline number: align the DENOMINATOR
A reference (e.g. the server team) often reports its rate on a **filtered
"qualified" subset**, not the full sample set — e.g. server headline 62.6%/68.4%
was on 4185 "qualified" backs (an independent qrdet/YOLO geometric filter kept
only cards where ≥3 QR symbols are physically detectable: 2 big + 1 small), while
the full set was 5927. Comparing your full-set rate to their qualified rate is
apples-to-oranges. To compare honestly:
1. Get their EXACT id list (`qualified_ids.txt`). **Search sibling dirs first** —
   it's usually already on disk under `backend/<name>/results/` or
   `ref_repo/<name>/results/` even if it wasn't committed to the repo you cloned.
   Don't regenerate a 6000-image YOLO pass if the list exists locally.
2. Restrict your per-image results to that id set and recompute. On this project,
   full-set 3.46%→23.52% became 4.87%→33.19% on the 4185 qualified denominator —
   same trend, higher numbers (the filter drops ~1742 un-decodable stills).
3. A residual gap after denominator-alignment is usually the **decode engine**,
   not your port: ZXing-Java (app-faithful) vs server zxing-cpp stayed ~35pp apart
   on identical qualified inputs. State that the app-faithful口径 is capped by the
   library the app actually uses; closing it means NDK-compiling zxing-cpp (which
   abandons "faithful to the app") or adding crop-localization / camera zoom.
- If you MUST regenerate the qualified list, note the qrdet/torch env pitfall
  below before installing.

## Env pitfall: torch/qrdet won't install on bleeding-edge Python
`pip install qrdet` (pulls torch + ultralytics) **hangs/backtracks forever** in a
venv built on a too-new Python (e.g. 3.14) because torch has no matching cpXX
wheel yet — pip silently resolves for minutes then fails. Fix: build a dedicated
venv on a supported interpreter (`python3.11 -m venv qrdet-venv`) and install
there. Don't diagnose it as a network problem; it's wheel availability.

## Cross-check & PII hygiene
- Cross-check on-device pass set vs JVM reference by ID intersection (expect exact
  match; report device-only / reference-only counts = 0 as the proof of no drift).
- Per-image result CSVs often carry real record IDs / decrypted content = PII.
  Strip the id column (keep an anonymized row index) before committing artifacts,
  even to a private repo.
