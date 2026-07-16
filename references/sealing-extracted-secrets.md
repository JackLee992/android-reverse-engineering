# Safely stewarding a secret extracted from an APK (seal, don't hardcode)

You reversed a private key / master secret embedded in a native lib (see
`recover-embedded-crypto-keys.md`). It's "already public" in the sense that
anyone can pull it from the APK — but that does NOT make it OK to paste plaintext
into your company repo. Once committed, a plaintext key lives forever in git
history and turns a code repo into a credential leak. This note is the disposal
discipline for the extracted material.

## The decision that saves the day: separate get-keys from use-keys

Before agonizing over how to store the private key, check whether your PRODUCTION
path even needs it. It usually doesn't:

- **get-keys** (rare, offline): private key → decrypt license/keystore →
  recover the working public keys. Runs only when the vendor rotates the license.
- **use-keys** (hot path): the recovered PUBLIC keys decrypt every real payload.
  Never touches the private key.

If use-keys only needs public material, persist the recovered public keys
(e.g. `data/native_keys_v2.json`, matching how the repo already stores old-card
public keys) and the hot path depends on ZERO secrets. The private key becomes a
rotation-only tool. Confirm this by tracing which function actually consumes the
private key — in the INE v2 chain it was ONLY `_unwrap_decoded_keys()` inside
`load_license_keys()`, never the per-card decode.

## Match the repo's EXISTING key convention, don't invent one

Grep first: `rg -l "BEGIN (PUBLIC|PRIVATE) KEY|RSAKeyValue|<Modulus>"`. The old
code path almost certainly already externalized its keys (old INE cards read
`dd_key1/dd_key2` public XML from `data/native_keys.json`, source did pure math
only). Follow that precedent — externalized data file for public keys, source
does computation — instead of a new scheme reviewers have to learn.

## Sealing pattern: ciphertext in repo, master key in env

For the private key that must be retained but never plaintext:

- **Ciphertext committed**: Fernet-seal it → `data/hbx_rsa_private.enc`. Safe to
  commit; useless without the master key. Fernet = AES-128-CBC + HMAC, in the
  `cryptography` lib most repos already have.
- **Master key out-of-band**: `HBX_MASTER_KEY` from env / secrets manager, in
  `.env` locally (which is gitignored — verify with `git check-ignore .env`).
- **Loader fails loud**: no master key ⇒ raise a clear error naming the doc, do
  NOT silently fall back to a plaintext constant.

```python
def _load_sealed_pem() -> bytes:
    master = os.environ.get("HBX_MASTER_KEY")
    if not master:
        raise SecretError("HBX_MASTER_KEY unset; see docs/SECRETS_*.md")
    enc = (Path(__file__).parent.parent / "data" / "hbx_rsa_private.enc").read_bytes()
    try:
        return Fernet(master.encode()).decrypt(enc)      # plaintext lives only in RAM
    except InvalidToken as e:
        raise SecretError("wrong HBX_MASTER_KEY (cannot open sealed key)") from e
```

Ship a one-shot `scripts/seal_secret.py` that reads the plaintext (from the old
source line, in-process — never echo it to stdout or shell history), Fernet-seals
it, round-trip-verifies, and writes the `.enc`. Then delete the plaintext
constant from source.

## Handling the plaintext without leaking it while you work

- Do NOT echo the PEM to a terminal (goes to scrollback / shell history) or into
  a tool result. `read_file` tools that redact `BEGIN PRIVATE KEY` blocks are
  doing you a favor — splice the secret programmatically (regex on the file
  bytes), never by pasting it into a new tool call.
- After sealing, `rg "BEGIN PRIVATE KEY" -l` the whole tree to confirm no
  plaintext residue (allow only the `.enc` and gitignored `.env`).
- Stage precisely: `git add` the specific files; NEVER `git add -A` when a `.env`
  or plaintext dump might be lurking. Re-verify `.env` is ignored before commit.

## Deliverable: a rotation runbook

Write `docs/SECRETS_*.md`: where the master key lives, how to sync it to the
server's secrets store, and the exact command sequence to run when the vendor
rotates the license (unseal private key → decrypt new license → dump new public
keys → commit the public-key JSON, NOT the private key). State plainly that the
hot decode path needs none of this.
