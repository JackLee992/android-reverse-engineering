# Recovering embedded/obfuscated crypto keys from a native lib (offline replication)

Goal: when an Android app's native `.so` does its own crypto (not a clean JNI to
a known lib), reverse the **key-derivation chain** so you can decrypt its payloads
**offline in Python**. Works because most such apps ship *all* key material inside
the APK/lib — either plaintext globals, or a lightly-obfuscated blob deobfuscated
at runtime. Real case: INE PersonalCode v2, `libl1I.so`, Chilkat-based.

## Method (IDA Pro MCP headless — see ida-pro-mcp.md for setup)

1. **Find the real crypto call sites, not the framework wrappers.** Chilkat/OpenSSL
   ship with named exports (`CkRsa_DecryptBytes`, `CkEcc_VerifyHashENC`,
   `CkCrypt2_SetEncodedKey`, `CkRsa_ImportPublicKey`). `xrefs_to` each PLT stub →
   the *app* callers are the orchestration functions worth reading. Ignore the
   1-line export thunks.
2. **Read the orchestrators top-down** with `decompile`. Look for the shape:
   import public key (XML/PEM) → `DecryptBytes(usePrivateKey=0)` = RSA *public*
   decrypt (same primitive as many INE-style schemes), or RSA-private-unwrap an
   AES key → `CkCrypt2` AES decrypt. Note error strings — they name the steps
   ("Missing RSA public key", "AES decrypt failed", "Latch size invalid").
3. **Extract embedded key material** with `get_bytes`/`get_global_value`/`get_string`
   and `decompile` of the C++ static initializer (`__cxa_atexit` blocks assign the
   globals). Plaintext PEM/XML keys and AES password constants live right there.
4. **De-obfuscate blobs by porting the transform verbatim.** If a key is stored
   obfuscated (e.g. NEON `vsubq_s8`/`veorq_s8`/`vsraq_n_u8` byte loop with a
   per-index counter starting from a `0..15` vector), copy the exact byte ops into
   Python (`rol8`, `+`, `^`, `-` all `& 0xFF`) and run over the `get_bytes` blob.
   You know you nailed it when the output is printable (`<RSAPublicKey>`, PEM header).
   Watch Python operator precedence: `(((x-c)&0xFF)+0x61)&0xFF` needs every mask.
5. **Reproduce the chain end-to-end against real data** with pycryptodome.
   RSA public "decrypt" = `pow(int.from_bytes(block),e,n)` per modulus-length block,
   then strip PKCS#1 (type-1: `00 01 FF..FF 00 data`; type-2 similar). OAEP unwrap =
   `PKCS1_OAEP.new(priv, hashAlgo=SHA256).decrypt`. Verify by decoding a real
   license/asset file to a sane JSON, not by round-tripping your own synthetic data.

## Two-layer "latch" RSA scheme (generalizes the legacy prefix scheme)

INE-style payloads: last modulus-length block is a "latch" decrypted with **key2**;
the remaining body is decrypted in modulus-length blocks with **key1**; output =
`key1_decrypt(body) + key2_decrypt(latch)`. Confirm layer↔block assignment at the
**instruction** level (`disasm`) — decompiler variable names lie in optimized code.
The legacy variant is the same idea with a *prefix* instead of a trailing latch.

## Strengthening synthetic round-trips: real plaintext + correct-bit-width keys

When you can't get the app's real *private* keys (they live server-side; RSA-8192
can't be factored) you cannot forge a genuinely-signed payload. But you can make the
round-trip far more meaningful than a toy self-encrypt by feeding it **real recovered
plaintext**: run the *working legacy* decrypt path over real sample cards to obtain
true plaintext card bytes, then re-encrypt that real plaintext with **self-generated
keys of the exact production bit-width** (e.g. RSA-8192, 1024-byte blocks) as the
inverse of the native decrypt, and assert your ported decryptor recovers it byte-for-byte.
This exercises real content + real bit-width + real cross-block PKCS#1 boundaries — a
much stronger self-consistency proof than 1024-bit synthetic filler. (Real INE case:
extracted 40 legacy card-back JPGs → 21 decoded to true plaintext via the legacy chain
→ latch-re-encrypted under fresh RSA-8192 → 21/21 recovered==original.)

Performance gotchas for big-modulus verification:
- `RSA.generate(8192)` is slow and highly variable (~30s–150s per key in pycryptodome).
  Generate ONCE, persist the PEMs to a temp/cache dir, reuse across runs. Don't inline
  keygen in every verify.
- Textbook private encrypt `pow(m, d, n)` (no CRT) at 8192-bit × many blocks takes
  minutes. Run keygen and the round-trip as **background processes** with a completion
  watch pattern; foreground calls will time out.

## Closing the loop: use the official app as a decryption ORACLE (reverse-validation)

Synthetic round-trips prove *decryptor self-consistency* but never the fragment-assembly
and field-parse layers, nor that the app's own logic matches your understanding. The
strongest validation available without a real signed sample is to **make the official app
decrypt a payload YOU synthesized** — if it parses your fields correctly, you've proven the
whole chain (assembly + latch decrypt + plaintext parse) in one shot, with the app itself as
ground truth. Since you lack the real *private* keys, you must swap the app's *public* keys
for your own and feed a payload built with your matching private key.

Prep / feasibility recon (do this BEFORE committing to a swap approach):
- Find the JNI entry from the decompiled Java facade, not just the `.so`. Grep the decompiled
  sources for `System.loadLibrary("<name>")` and `native` method decls. Real case: the class
  loading `libl1I.so` exposed `private native String pc(Activity, List<byte[]>, boolean)`
  taking QR fragment byte[]s and returning decoded JSON (`{text,image[],personalcode_id}` or
  `{status,description}`). That `pc`/JNI method is the oracle: feed fragments, read JSON.
- Confirm the decode path is **offline-reachable** (doesn't phone the server / device-attest)
  before building anything — otherwise the oracle is unusable. A no-op Frida trace of the JNI
  method on the real app answers offline-reachability + hookability + real input/output byte
  shape in one zero-risk step. Do this recon trace first.

Two key-swap mechanisms (prefer Frida when the device is rooted):
- **A. Frida runtime hook (light, iterate fast, no re-sign):** hook the point in the `.so`
  where layer pubkey XML/PEM is imported (right after the derivation chain yields `decodedKeys`)
  and replace with your pubkey; also hook/neuter the license-signature check so it passes.
  No file changes, reversible, best for iteration. Needs root or frida-gadget repack.
- **B. Repackage APK (heavy):** replace `assets/license.txt` + patch the embedded RSA/EC
  verify pubkeys in the `.so` to yours, re-sign, install. "Cleaner" but forces forging the
  whole signature chain and is slow to iterate. Fall back to B only if A's hook point resists.

Environment gotchas learned here:
- Device root varies: `adb root` only works on userdebug builds and will *drop the device
  offline* on production ROMs — don't use it; probe `su -c id` (expect `uid=0`) and
  `/system/bin/su` / `/data/adb/magisk` instead. Device serial can change across a
  reboot/reconnect (e.g. wireless adb short id vs USB serial) — re-confirm `ro.product.model`
  after any reconnect; you may be talking to a *different* device than last call.
- frida-python must match the host frida CLI version exactly (`pip install frida==<cli ver>`);
  push the arch-matched `frida-server-<ver>-android-arm64` to the device.
- The write_file tool refuses system temp paths (`/var/folders/...`); create scratch scripts
  there via a terminal heredoc instead.

## Honesty / evidence discipline (user is evidence-first)

- The key-derivation chain is provable offline against a real license/asset file →
  that's a **real** result, state it as such.
- Payload decryption you can only round-trip with *synthetic* keys — even with the
  real-plaintext + correct-bit-width upgrade above — is **decryptor self-consistency**,
  NOT end-to-end verification. It proves your ported crypto/block-order/padding is
  correct at production scale; it does NOT prove the fragment-assembly and plaintext
  field-parse layers, nor that a real signed card decodes. Name both layers and mark
  "real signed sample" as the concrete remaining blocker. Do not claim end-to-end.
- Faithfulness rule: replicate the app's actual primitive (same lib, same padding,
  same block order). Do NOT substitute a "stronger"/different server-side scheme.
- Write the RE report in Chinese into the project's `docs/` with an address cheat-sheet
  (JNI entry, each orchestrator, each embedded-key global) so the chain is auditable.
