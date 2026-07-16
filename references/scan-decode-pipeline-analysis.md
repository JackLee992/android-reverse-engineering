# Analyzing QR / Barcode / Scan-Decode Pipelines in Decompiled APKs

Use this when the question is "what library does the scanning, how is recognition
done, and is there any quality/restriction gate" — a recurring class of request for
camera-scan apps (QR validators, ticket scanners, ID readers, payment scanners).

## Step 1: Fingerprint the decode library by package + class names

Obfuscation usually renames the *app* package (control-flow flattening, junk
arithmetic like `int i2 = (i ^ 89) << 1 ... % 128`, wall-to-wall try/catch), but
**third-party library packages and their public API are typically NOT obfuscated**.
Search `sources/` for these package roots to identify the engine fast:

- `com/google/zxing` → **ZXing** (the decode core). Sub-packages tell you formats:
  `qrcode`, `oned`, `pdf417`, `datamatrix`, `aztec`, `multi/qrcode` (multi-code).
- Camera wrapper is often a **renamed fork of zxing-android-embedded**
  (journeyapps) or the older `me.dm77.barcodescanners`. Even when the fork's own
  package is renamed (e.g. `com.hubox.camera`), the class names survive and map
  1:1 to the upstream lib: `CameraInstance`, `CameraManager`, `DecoderThread`,
  `DecoratedCameraPreview`, `AmbientLightManager`, `AutoFocusManager`,
  `framingRect`, `PreviewScalingStrategy`, `RawImageData`. Recognize the fork by
  this class-name constellation, not the package.
- ML Kit: `com.google.mlkit.vision.barcode`. Firebase: `com.google.firebase.ml`.

Confirm with: `search_files pattern="import com\.google\.zxing[^;]*" path=<app pkg>`
to see exactly which ZXing classes the app's own code pulls in
(`QRCodeMultiReader`, `HybridBinarizer`, `RGBLuminanceSource`,
`PlanarYUVLuminanceSource`, `DecodeHintType`).

## Step 2: Do NOT assume the native .so files do the decoding

Obfuscated `.so` names (`libda0.so`, `liba8075.so`, `libeb0846.so`) are tempting to
blame for "the real recognition." Usually they are **not** the decoder. Grep the
JNI bridge classes for the `native` method names and the `System.loadLibrary`
call site:

```
search_files pattern="loadLibrary|native |System\.load" path=<lib bridge pkg>
```

If the native methods are named like `getRemaining`, `hasRemaining`, `updateCtr`,
`acc(...)`, `hayRestantes`, or take an `Activity` — they are **licensing / usage-quota
counting, anti-tamper, and credential (crypto) validation**, not image decode.
A `getApplicationInfo().flags & 2` check inside the JNI class = debuggable / anti-debug
guard, another tell it's a protection lib. The decode almost always stays in the Java
ZXing path; the `.so` verifies the *decoded payload* (`getRawBytes()` → native `acc()`).

## Step 3: Trace the per-frame decode path

Follow: `Activity` → camera `Fragment`/`ParametrosScanner` → `DecoderThread`
(background `HandlerThread`) → `onCameraFrame(CameraData)` → the app's `decode(...)`
wrapper → `QRCodeMultiReader.decodeMultiple(binaryBitmap, hints)` (or
`MultiFormatReader.decode`). The `BinaryBitmap` is built from a `LuminanceSource`
(`PlanarYUV...` for live preview, `RGBLuminanceSource` for stills) wrapped in a
`HybridBinarizer`.

## Step 4: Locate the "quality / restriction" logic (the usual real question)

There are only a few places a quality gate could live — check each and report
presence/absence explicitly:

1. **Decode hints**: `DecodeHintType.TRY_HARDER = true` means the OPPOSITE of a gate
   — it *widens* tolerance for poor codes. `PURE_BARCODE` restricts to clean codes.
2. **Frame prep in `getBitmap()` / `createYUVLuminanceSource()`**: check `inSampleSize`
   (downsampling), JPEG `compressToJpeg(rect, quality, ...)`, and the `cropRect`.
   A crop of `(0,0,width,height)` = full frame, no region restriction.
3. **Framing rect / scan window**: `getPreviewFramingRect()`, `framingRectSize`,
   `marginFraction` — restricts *where* it looks, not code quality.
4. **Auto-zoom / focus aids**: resolution-tiered zoom (e.g. width ≥2000 → 2.5×,
   ≥1500 → 2.2×, ≥900 → 1.8×), `autoFocusEnabled`, `AmbientLightManager` (low-light
   torch). These are recognition *aids*, not quality filters — say so.
5. **True gates to search for and usually NOT find**: `minModuleSize`, min width/height
   thresholds, sharpness/blur/`calidad`/`nitidez`/`distancia`, "too small/too far".
   If none exist, the honest answer is "no image-quality gate; the app instead relaxes
   and boosts recognition." Distinguish this from a **business quota limit** (native
   `getRemaining`/`hasRemaining` → "validations exhausted" screen), which is unrelated
   to image quality.

## Step 5: Note the network posture

Grep `AndroidManifest.xml` for `INTERNET` / `ACCESS_NETWORK_STATE`. Absence = fully
offline decode+validation (common for gov ID validators). Combined with no URLs in the
app code, you can state definitively that recognition and validation are local.

## Reporting shape (matches how these requests are phrased)

Deliver three labeled sections: **(1) what library** (table: ZXing core + camera fork +
role of each `.so`), **(2) how recognition is done** (call chain + the specific
`Reader`/`Binarizer`/hints), **(3) is there a quality gate** — a direct yes/no with the
searched-for gate names, clearly separating recognition-aids and business quotas from
actual image-quality restrictions. Offer an IDA/MCP handoff for the `.so` only if the
user wants the credential-verification algorithm.
