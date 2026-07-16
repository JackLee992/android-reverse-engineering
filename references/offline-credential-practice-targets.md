# Offline Credential / Scan-Decode Practice Targets (Megvii backend expansion)

Use this when you want RE practice targets **structurally identical to the INE
voter-card task** — an offline-verifiable signed credential encoded in a QR /
barcode / NFC tag that a backend must decode, verify, and extract fields from.
This is the class of work a Megvii ID/credential backend can horizontally
expand into. Every target here maps to a skill you already exercised on INE:
`scan-decode-pipeline-analysis`, `recover-embedded-crypto-keys`,
`reverse-columnar-binary-format`, `native-oracle-validation`, and the design
lessons in `client-side-crypto-design`.

## Legal boundary (read first)

RE legality depends on **target ownership + purpose**, not the technique. Stay
in these lanes:
- Your own / company-authorized apps and SDKs.
- **Published open standards** — decoding a credential whose format is a public
  spec is study, not circumvention.
- Purpose-built ranges (crackmes, CTF) and in-scope bug-bounty targets.

Do NOT: forge credentials, defeat an issuer's signature to mint fakes, or
extract another person's PII from a live credential you don't own. The INE work
was legitimate because there was a real product need to *decode* new cards — the
same "decode + verify, never forge" framing applies to everything below.

## Why this class fits Megvii

INE proved the pipeline: **QR frames → assemble → decrypt/verify signature →
parse proprietary container → extract fields (incl. biometrics like fingerprint
minutiae)**. A backend that does this generalizes to any government / travel /
health credential. The high-value differentiator: most modern credentials pair
the document with a **face/liveness check** (the holder-binding step), which is
exactly Megvii's core. Decode + verify + face-match is one coherent product.

## Targets, ranked by structural match to INE

### Tier A — standardized signed credentials (closest fit, fully legal to study)

These are the "how INE *should* have been built" reference implementations:
open spec + official verifier apps + real deployments. Decoding them teaches the
standard-scheme side of `client-side-crypto-design` (COSE_Sign1 / CBOR / mdoc)
so you feel the contrast with INE's bespoke latch/FPC6.

1. **ICAO DTC / eMRTD (ePassport chip + VIZ + MRZ)** — ISO/IEC 7501, ICAO Doc
   9303. NFC (ISO 14443) chip with BAC/PACE + Passive/Active Authentication;
   the data groups include the face image (DG2) and fingerprints (DG3). This is
   the flagship: offline PKI-signed identity + biometrics, exactly INE's shape
   at national scale. Practice on **your own passport** + open-source stacks
   (`pyMRTD`, `jMRTD`, `pypassport`). Skill map: NFC/APDU + PKI verify + biometric
   field extraction → direct Megvii ID+face product.

2. **ISO 18013-5 mobile Driving License (mDL / mdoc)** — CBOR + COSE_Sign1,
   device engagement over QR/BLE/NFC, selective disclosure, holder binding.
   Reference: the ISO spec, `mdoc`/`mDL` open implementations, and the AAMVA
   test vectors. This is the modern gold standard; decoding it is the positive
   training complement to INE's negative example.

3. **EU Digital COVID Certificate (EU DCC)** — the cleanest, easiest entry:
   base45 + zlib + COSE_Sign1 + CBOR, public signing certs, tons of open
   decoders. A weekend to fully decode. Best *first* Tier-A target to internalize
   the COSE/CBOR pipeline before the harder ePassport/mDL work.

4. **SMART Health Cards / SHC (W3C VC + JWS)** — QR-encoded signed health
   credential, JSON+JWS. Different signature envelope (JWS vs COSE) — good for
   breadth on credential signature formats.

### Tier B — proprietary offline credentials (INE-like: reversing required)

These use undocumented/proprietary encoding like INE's FPC6, so they exercise
`reverse-columnar-binary-format` and `native-oracle-validation`. Only study ones
you legitimately possess and where decoding serves a real product need:

- **Other national ID QR/barcodes** (Aadhaar QR India, various LatAm/SEA voter &
  national IDs). Many publish partial specs (e.g. Aadhaar Secure QR is
  documented); some are proprietary. Same "assemble → verify → parse" chain as
  INE. Megvii-relevant wherever the backend must onboard a new country's ID.
- **PDF417 on driver's licenses (AAMVA DL/ID)** — North American DLs carry an
  AAMVA-standard PDF417 barcode; spec is public. Easy decode, good for the
  barcode-assembly + field-map muscle.
- **Boarding passes (IATA BCBP)** — public spec, PDF417/Aztec/QR. Trivial but a
  clean warm-up for multi-format barcode assembly.

### Tier C — NFC / transit / access credentials (offline key + proprietary format)

Same "offline key + bespoke format" shape as INE, on NFC hardware. Practice on
**your own cards** with a Proxmark3 / an NFC-capable phone:
- Transit cards, hotel keys, office access (MIFARE Classic/DESFire). Teaches
  offline key derivation, APDU, and sector/file parsing — the NFC analog of
  INE's key-group + latch scheme.

## Recommended path for the team

Run two tracks in parallel, mirroring the INE positive/negative pairing:

1. **Positive track — decode one Tier-A standard end-to-end.** Start with EU DCC
   (fastest), then ISO 18013-5 mDL or an ePassport. Build a backend decoder that
   verifies COSE_Sign1/JWS against the published trust list and extracts fields.
   This is directly shippable Megvii capability and grounds every "do it this
   way" claim in `client-side-crypto-design` in real code.
2. **Negative track — reverse one Tier-B proprietary credential you must
   support.** Same workflow as INE: `scan-decode-pipeline-analysis` →
   `recover-embedded-crypto-keys` → `reverse-columnar-binary-format` →
   `native-oracle-validation`. Produces both training and a real backend feature.

The product thesis that ties it together: **decode + verify + Megvii
face/liveness holder-binding** = a complete credential-onboarding backend.
ePassport DG2/DG3 (face + fingerprint) and mDL portrait are where the document
side meets Megvii's biometric core.

## Spec entry points (bookmarks)

- ICAO Doc 9303 (eMRTD) — icao.int/publications/pages/publication.aspx?docnum=9303
- ISO/IEC 18013-5 (mDL) — iso.org; AAMVA mDL test vectors — aamva.org
- EU DCC — github.com/ehn-dcc-development (schemas + test data)
- SMART Health Cards — spec.smarthealth.cards
- AAMVA DL/ID PDF417 — aamva.org (DL/ID Card Design Standard)
- IATA BCBP — iata.org (Resolution 792)
- Aadhaar Secure QR — uidai.gov.in (developer docs)
