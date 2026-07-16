# Validating reverse-engineered crypto with the official app as an oracle

When you've reverse-engineered a decrypt/parse chain out of a native `.so` and
ported it (e.g. to a Python backend), the strongest possible verification is to
make the ORIGINAL app confirm your understanding — it removes your own RE from
the loop. Two complementary techniques.

## 1. Self-consistency round-trip (no device needed)

If you cannot get a real production input sample, invert your own decoder:
- Take real plaintext you CAN obtain (e.g. decode legacy-format samples with the
  already-working path).
- Encrypt it with a **self-generated keypair** at the real bit-width / block
  size, following the exact scheme you reversed (block layout, concatenation
  order, padding).
- Run your ported decoder with the paired key; assert `recovered == original`.

This proves the codec's block math / key assignment / concat order is correct at
real scale. Be honest about the boundary: it proves your decoder is
self-consistent, NOT that your understanding of the real input framing /
plaintext layout is right. State that explicitly.

Pitfall: RSA-8192 keygen is minutes-long and non-CRT `pow(m,d,n)` private
encryption per block is very slow — generate keys once, persist to disk, and run
the round-trip as a separate step (background process). Don't regenerate keys
per run.

Concrete forward-forge recipe (inverse of an app that PUBLIC-decrypts blocks):
the app does `plain = pow(cipher, e, n)` then strips PKCS#1 type-1 padding, so to
forge a block the app will accept you PRIVATE-encrypt: pad as
`00 01 FF..FF 00 <msg>` to the modulus width (chunk `<= modlen-11` bytes), then
`cipher = pow(padded, d, n)`. Concatenate blocks in the exact order/segmentation
the decrypt reverses (e.g. a two-layer "latch": front chunks -> layer1 blocks, a
`<= modlen-11`-byte tail -> one layer2 block, `payload = body_cipher ++
latch_cipher`). Round-trip against your ported decoder at sizes that straddle
block boundaries (1, modlen-11, modlen-10, N*block, ...) before touching the
device.

## 1b. App-as-oracle with REAL inputs (no key-swap — try this FIRST)

Before reaching for key substitution, check whether the app can decode a *real*
sample on its own. If the decrypt keys are **embedded in the app** (public keys
baked into the `.so`, not fetched per-request), then any genuine captured input
the app would normally accept is decodable offline with zero key manipulation.
This is by far the cleanest oracle: feed the app real fragment bytes, let its own
native lib do assembly+decrypt+parse, and read back the plaintext.

Workflow that worked end-to-end (INE QR decode, `com.personalcode.Azf`):
1. Use YOUR extractor to turn the source artifact (card JPG) into the same raw
   byte payloads the app's scanner produces (QR fragments — Reed-Solomon output
   is library-independent, so zxing-cpp vs the app's decoder give identical
   bytes).
2. Base64 the fragments over the RPC boundary, rebuild them device-side into the
   exact arg type the native method wants (`ArrayList<byte[]>` via
   `android.util.Base64.decode`).
3. Invoke the **private native** method directly through the Java bridge — no
   reflection needed. frida's `Java.use` exposes private methods and resolves
   overloads: `Azf.$new().pc(activity, list, z)`. Do NOT use
   `clazz.getDeclaredMethod(...)` — it throws `argument types do not match` when
   you pass JS values for a `Class[]`.
4. Getting the `Activity` arg without UI: walk
   `ActivityThread.currentActivityThread().mActivities.value.values()`, cast each
   to `ActivityThread$ActivityClientRecord`, take the first non-paused
   `.activity.value` (fall back to index 0).
5. The native return may not be your final plaintext — trace the Java caller to
   see post-processing. Here `pc()` returns an encoded blob that a sibling native
   fn (`gTxt`) turns into the pipe-delimited text; a `z=true`/`z=false` flag
   selects branches. Reproduce the caller's exact sequence, don't stop at the
   first native return.

### FIRST confirm WHICH native path a sample actually exercises (version-adaptive apps)

A newer app version is often **format-adaptive**: it inspects the input header and
routes legacy-format inputs down the OLD decode path even though it also ships the
new (e.g. v2/latch) path. Consequence: decoding a real sample through the new app
shell does NOT prove the new path works — the shell version tells you nothing about
which branch executed. This bit us: a "10/10 field-for-field oracle match" on app
2.0.22 was actually validating the LEGACY dd-key path; the v2 latch/key-swap
functions never ran.

Before building any forge/key-swap to validate a NEW path, spend one cheap recon
step to prove routing. Hook the candidate path's key functions (assembly, decrypt,
key-import, JSON-parse) AND the JNI entry, then drive a real decode and **count
invocations per hook**:
- entry fires `1x` but the new-path fns fire `0x` → your samples take the OLD path;
  you have NOT tested the new path and never will with these samples.
- Only when the new-path fns actually fire is the app truly exercising that code.

Also verify offsets aren't stale: if the entry hook fires but nothing else does,
distinguish "wrong path" from "bad offsets" by confirming the entry hook (known to
execute) triggers — a live entry hook proves offset resolution is correct, so `0x`
on the others is genuine non-execution, not a broken address. Corollary: to
validate a new path you must forge an input whose header makes the router ENTER
that branch (look for version-gate strings like "Unsupported ... version",
"...NoHeaders"), not merely encrypt with new-path keys.

### Field-for-field diff catches port fidelity bugs

Once the oracle works, run BOTH your port and the app on the same real samples
and assert `ours == app` **char-for-char**, not just "both produced something".
This is where the oracle earns its keep: on a 10-sample batch, 8 matched and 2
differed by a single trailing space — our port emitted a 6-bit padding space that
the app's native `gTxt` trimmed. That is a real (if tiny) fidelity bug the diff
surfaced. When you see a DIFF, check whitespace/padding first (`repr()` the
tails); padding artifacts at buffer boundaries are the common culprit, and the
faithful fix mirrors what the app does (here, `rstrip(" ")` — safe because the
last real field was a hex hash that never ends in space). Package the oracle as
two scripts: a single-shot decoder and a batch comparator whose exit code is
the pass/fail signal.

## 2. App-as-oracle via key substitution (the definitive test)

You almost never have the vendor's PRIVATE keys (they live server-side; large RSA
is unfactorable), so you cannot forge a genuine production payload. Instead,
swap YOUR public keys into the running app and feed it a payload you built with
your matching private key. If the app decodes it correctly, every layer you
reversed (fragment assembly + decrypt + plaintext parse) is confirmed at once.

Recon before committing (all zero-risk, do these first):
1. **Offline-reachability**: launch the app with no network (`monkey` shows
   "network not connected"); grep the decode package for retrofit/okhttp/URL
   classes. If decode needs a server, the oracle plan is dead.
2. **Can you hook the native fns**: resolve `libX.so` base, add IDA offsets,
   install `Interceptor.attach` on entry/parse/decrypt fns; a clean
   `hooks_ready` with base resolved is the green light.
3. **I/O byte shape**: read the actual key material and plaintext at the hook
   points to confirm your model.

Key-swap hook points (generalize from this session's Chilkat-based app):
- The fn that imports the layer public key XML string (`CkRsa::ImportPublicKey`)
  — overwrite the incoming XML arg with your own public key.
- The signature-verify fn (`CkEcc::VerifyHashENC`) — force return 1 to bypass
  the license/signature trust chain you can't satisfy.

Scope the forge HONESTLY before committing: a real v2 plaintext may be a deep
multi-stage pipeline, not a single decrypt. Here it was latch-decrypt -> TLV
frame parse -> field-extract -> an INNER X.509 cert-chain verify
(`CkCert::VerifySignature` + `VerifyCertSignatures` + `IsRootTrusted` against the
license `rootCer`) gating an `ok` flag. Each unforgeable trust gate you can't
satisfy (root-CA chain, license `firma`) needs its own bypass hook. Count them
up front: when you're hook-bypassing 4-5 gates (tamper gate, key-group, key-swap,
license sig, X.509 chain), "the app is validating for us" is mostly gone — the
only thing still genuinely endorsed is the DATA-TRANSFORM layers you didn't
bypass. Often the highest-value target is to isolate-verify just the one crypto
layer you actually ported (read the app's decrypt output at that fn's exit and
assert `== your_plaintext`) rather than forging a full end-to-end card.

### Let the app's own error emitter navigate the forge (iteration loop)

Chilkat/C++ decoders funnel every rejection through one `noreturn` error emitter
(here `sub_206364(int code, std::string* msg)` which throws). Hook it and print
`(code, msg)` — each forge attempt then tells you the EXACT next thing to fix
("Unsupported Personal Code version: 16", "Empty BINARY frame", "Invalid
Signature", "Personal Code headers truncated (validFrom)"). This turns blind
structure-guessing into a guided loop: feed candidate -> read reject string ->
adjust one field -> repeat. Combine with a per-stage call-counter so you see how
far the payload got before the throw. The emitted string often reveals the
plaintext's field names and header layout for free.

### Reading a libc++ std::string* arg in Frida (SSO vs heap)

Many of these fns pass `std::string*`, not `char*`. Reading it as a C string
gives garbage (we first read a reject msg as `'1'`). libc++ layout: read the
first byte — if `(first & 1)` it's LONG form `[cap][size][data*]` (data at
`p + 2*ptrsize`, size at `p + ptrsize`); else SSO, `size = first >> 1` and chars
start at `p + 1`. To OVERWRITE with your own value (key-swap): do NOT swap in a fresh
`Memory.allocUtf8String` buffer and repoint `data*` — the app's std::string
destructor will then `free()` YOUR frida buffer and crash (this bit us: keyswap
succeeded then the process died mid-decode). Instead write IN PLACE into the
app's own already-allocated buffer, which is safe when your string fits its
capacity. The incoming key XML is typically long-form with cap ~1441 and your
key XML is shorter, so:
```js
const isLong = (p.readU8() & 1) === 1;
const cap = isLong ? (p.readU64().toNumber() & ~1) : 22;   // mask off long-flag bit
const dataPtr = isLong ? p.add(2*ptrsize).readPointer() : p.add(1);
if (pick.length + 1 <= cap) {          // fits -> overwrite in place, keep the pointer
  dataPtr.writeUtf8String(pick);
  if (isLong) p.add(ptrsize).writeU64(pick.length);   // update size only
  else        p.writeU8(pick.length << 1);
}
```
Only fall back to repointing `data*` if your string exceeds `cap` (then you must
also neutralize the destructor, which is fiddly — prefer keeping payloads short).

Python-side gotcha: build the frida agent JS with `.replace('__TOKEN__', ...)`,
NOT `%`-formatting — the JS contains literal `%` (e.g. `swapN % 2`) that breaks
`AGENT % (...)` with "not enough arguments for format string".

### Three key-swap execution bugs a successful latch-oracle hits (in order)

Once the in-place overwrite works, expect these three in sequence — each throws a
distinct emitter code, so hook the error emitter to see which you're on:
1. **Wrong key-XML root tag** -> "Unable to import RSA public key" (code 303).
   Chilkat's `CkRsa::ImportPublicKey` wants `<RSAPublicKey><Modulus>..</Modulus>
   <Exponent>..</Exponent></RSAPublicKey>`, NOT the .NET `<RSAKeyValue>` root.
   Confirm by logging the app's OWN incoming XML at the hook before overwriting
   (`readStdString(a[1])`) and copy its exact root tag.
2. **Wrong key ORDER for multi-layer schemes** -> "Unable to decrypt block with
   public key" (code 305) on the 2nd+ import. A latch decrypts the TAIL block
   first (layer2) then the BODY blocks (layer1), so the 1st `ImportPublicKey`
   call must get layer2's XML, later calls layer1's. Track a swap counter and map
   call-index -> key; backwards decrypts one layer with the wrong modulus and
   faults in PKCS#1.
3. **Empty degenerate block** -> also code 305, but only when the whole plaintext
   fits in the tail so the BODY is empty. Chilkat rejects an empty-message block.
   Force a non-empty body: pick `latch_tail_len < len(plaintext)` so at least one
   full body block exists. Sweep sizes straddling block boundaries
   (body=1000/1200/3000...) and assert the app's decrypt output == plaintext at
   each — a clean multi-size byte-for-byte match is the definitive GREEN.
After the latch layer verifies, the app rejecting the (random) plaintext at the
NEXT stage (e.g. "TLV length exceeds buffer") is EXPECTED and is itself proof the
latch layer was cleanly traversed — the garbage only fails above the layer you
were validating.

### Frida 17 dropped the Java bridge — two ways to drive the decode

Frida **17.x removed the bundled Java/ObjC bridge** from the agent runtime, so a
bare `create_script` gets `ReferenceError: 'Java' is not defined`. Native
`Interceptor.attach` hooks still work fine on 17.x (they're bridge-independent),
but you lose `Java.use(...)` — which is the cleanest way to *invoke* the decode
JNI method directly with a constructed `List<byte[]>` instead of driving the
camera UI. Two options:

- **(A) Downgrade both sides to 16.x (recommended when you can get the binary).**
  The Java bridge lives inside the device-side `frida-server`, so you need the
  matching `frida-server-<ver>-android-arm64.xz` (NOT the `-devkit-` asset — that
  is a host build SDK `.a`+header, useless for this). Push it, kill the 17.x
  server, run the 16.x one, and `pip install frida==<same ver>` in the host venv
  (major.minor must match device). Then `Java.use("com.x.Azf")` resolves and you
  can call the native method with real fragment bytes, no UI. On locked-down
  networks the release asset download is the hard part — have the user attach the
  exact `.xz` if proxies truncate it.
- **(B) Stay on 17.x, construct the call through raw JNI from native** (FindClass
  / NewObjectArray / CallObjectMethod via NativeFunction on the JNIEnv vtable).
  More glue code; only worth it if you truly can't get the 16.x server.

Attach gotcha (MIUI/HyperOS): `dev.spawn([pkg])` often fails to resolve the
launch intent (`unable to find application`). Launch via
`adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`, then
`enumerate_processes()` and attach by PID — note the process **name is the app
label** (e.g. `Valida INE-QR`), not the package id. Installing split APKs: use
`adb install-multiple base config.arm64_v8a config.<lang> config.<dpi>`; the `-g`
(grant-all-perms) flag can throw on some splits, so drop it if install-create
fails.

### Reading a jstring in native-only Frida (no Java bridge)

JNI passes `jstring` as an opaque pointer. To read it without the Java bridge,
call `GetStringUtfChars` through the JNIEnv vtable:

```js
// env = JNIEnv* (arg to the Java_* export, usually args[0])
const GetStringUTFChars = new NativeFunction(
  Memory.readPointer(Memory.readPointer(env).add(169 * Process.pointerSize)),
  'pointer', ['pointer','pointer','pointer']);
const cstr = GetStringUTFChars(env, jstr, NULL).readCString();
```

Index 169 is `GetStringUTFChars` in the JNINativeInterface vtable (stable).
For simpler cases the arg may already be a `std::string` / C-string in native
code — just `.readCString()` / `.readByteArray()` at the pointer.

### Anti-tamper gate

Native decode entrypoints often call a root/debug/emulator check first
(strings like "Rooted devices are not allowed", "Debugging is not allowed").
When invoking the JNI export directly (bypassing UI), either hook that gate to
return the allow value, or pass whatever the app passes — inspect the gate fn
first rather than guessing at a null Activity arg.

Concrete pattern that worked: invoking `pc(null, list, false)` with a null
Activity made the first-line gate (`sub_24D0B0`) return 0 (deny), so `pc()`
bailed with `{"status":2,"description":""}` before ANY decode ran — looks like a
decode failure but is really the tamper gate. Force-allow it in the hook's
`onLeave`, don't fight the null arg:
```js
Interceptor.attach(base.add(GATE_OFF), {
  onLeave: function (r) { r.replace(ptr(1)); }   // 1 = allowed
});
```
After this the router advanced into the real decode chain. So when a
direct-JNI call returns an instant generic error, hook the gate's RETURN before
assuming your input is malformed.

## 3. Forge-PoC staging: prove ROUTING before building a full forge

Building a full valid forged payload (correct plaintext layout + latch encrypt +
key-swap + sig-bypass) is a multi-hour push. De-risk it first with a cheap
routing-only PoC: forge a **minimal fragment set with a valid header but random
body**, feed it, and confirm the app's router ENTERS the target branch (the
new-path fns fire in sequence) before crashing inside the parser on the garbage
body. Reaching `assembly → json-parse` and then faulting on random bytes is the
GREEN LIGHT — it proves the header/routing model without needing valid crypto.

Header reversing that unlocked this (INE v2, `sub_21A278` + `pc()` a5-branch):
`byte0`=total fragment count (must be 1..6 and equal #fragments), `byte1`=index;
frag0 `byte2/byte3` select the key group (`group=((b3>>1)&7)+base`,
`variant=b3>>4`, and `(b2<<8|b3)` must be `<= 0x6F` or "Invalid Key Group").
Testing two variant bytes (one accepted, one rejected with a clean error) is a
bonus proof that per-header key derivation is real.

Crash-safe tracing: a garbage body WILL crash the native parser, which destroys
the frida script and makes a **synchronous** RPC (`exports_sync.run`) throw
`script has been destroyed` — losing the trace. Instead stream each hook hit via
`send({tag})` fire-and-forget and collect messages on the Python side with a
short `sleep`; streamed events arrive before the crash and survive it. Relaunch
the app between crashing runs (`monkey ... LAUNCHER 1`).

## 3b. Count your bypass hooks — they erode what the oracle proves

Before committing to a full forge, map the ENTIRE plaintext pipeline, not just
the crypto layer you ported. Trust gates you cannot satisfy (because you lack the
vendor's private keys) must be hook-bypassed, and each bypass subtracts from what
the app is actually validating for you. In the INE v2 case the post-latch chain
turned out to be 3 stages + an inner **X.509 cert-chain verify** (`CkCert::
VerifySignature` + `VerifyCertSignatures` + `IsRootTrusted` against the license
rootCer) — unforgeable without INE's root CA key. A full end-to-end forge would
have needed ~5 bypass hooks (tamper gate, key-group, layer key-swap, license sig,
X.509 chain). At that point the app is barely "verifying" anything: the only
layers still genuinely exercised are the data transforms (latch/TLV/field/text/
image), while every trust decision is stubbed.

Decision rule: when bypass hooks pile up, DON'T build the maximal forge. Isolate
the ONE layer you actually ported and verify just that, reading the app's real
output at that layer's boundary. Concretely — to validate a ported `latch`
decrypt: key-swap the layer public keys, feed a payload you built with your
matching private key, and hook the NEXT stage's input (`Interceptor.attach` on
the stage-2 entry) to read the app's latch-decrypted bytes and assert
`== your_plaintext`. This proves the ported layer with native RSA backing, needs
no TLV/field forging, and keeps the evidence boundary crisp. Reserve the full
multi-hook forge only when the parse layers themselves are what you ported and
must validate.

## 4. Headless idalib decompile from an existing .i64 (no GUI, no MCP)

When the IDA MCP server isn't loaded this session but you have IDA Pro + an
existing `.i64`/`.so`, decompile targeted functions headlessly via idalib. Run
with the IDA app's bundled python (has the `idapro`/`ida_hexrays` modules the
venv lacks):
```python
import idapro, ida_hexrays, ida_funcs
idapro.open_database("/path/libX.so", True)   # True = run auto-analysis
ida_hexrays.init_hexrays_plugin()
for ea in (0x20111c, 0x244324):
    f = ida_funcs.get_func(ea)
    cf = ida_hexrays.decompile(f)
    print(hex(ea), str(cf))            # dump to JSON for later reading
idapro.close_database(False)
```
Invoke as `"/Applications/IDA Professional 9.3.app/Contents/MacOS/idalib/python/python3" dump.py`
(the sys.prefix RuntimeWarnings from running that interpreter outside its venv
are harmless). Dump big functions to a JSON file and read offsets from there —
Hex-Rays truncates long bodies inline, so paging a saved dump beats re-calling.
Use this to resolve router/fork logic (e.g. an `a5`/`z` JNI param that selects
legacy-vs-new path) that static grep can't settle.
