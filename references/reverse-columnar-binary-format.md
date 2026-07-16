# Reversing a proprietary in-house binary container (columnar / bit-packed)

When the payload after your crypto layers is NOT a standard format (protobuf,
JSON, ASN.1) but a vendor's own packed binary — e.g. INE PersonalCode v2's
`FPC6` columnar container — you reverse the *serializer*, not a spec. This is
pure static work once you have the decompiled writer/reader in IDA.

## Find the reader, not the writer, if you can

The app almost always has BOTH an encoder (build card) and a decoder (parse
card). Reverse the **decoder** for a parse-only port — it's the ground truth for
field layout and it's what you actually need. Grep decompiled names / string refs
for the magic tag (`"FPC6"`, a 4-byte header const) and the struct field setters
(`setApellidoPaterno`, `setCurp`…) to land in the parser. The Java-side caller
(post-JNI) shows you the field ORDER and post-processing (trim, charset).

## Columnar layout: header table, then column blobs

In-house containers are often columnar (all values of field A, then all of B)
rather than row-wise TLV. The shape that recurs:

```
magic (4B "FPC6") | version | record_count | column_count
column_descriptor[column_count]:  { field_id | type | offset | length | flags }
column_data_blob[column_count]  (concatenated, each sliced by its descriptor)
```

Reverse the descriptor struct FIRST (its stride is a fixed int in the loop:
`ptr += 0x10` ⇒ 16-byte descriptors). Every field read is `blob[desc.offset :
desc.offset+desc.length]` — so once the descriptor table parses, the rest is
slicing. Write the descriptor parser, dump the table from a real (or app-oracle)
sample, and print `(field_id, type, offset, len)` before decoding any values.

## Bit-packed columns: nail endianness AND bit order

Numeric / enum / biometric columns get bit-packed (e.g. fingerprint minutiae:
`x:9bits, y:9bits, angle:8bits, type:2bits` → 28 bits/point, not byte-aligned).
Two independent axes to fix, and getting either wrong yields plausible-looking
garbage:

1. **Byte endianness** of the backing integer (big vs little).
2. **Bit fill order** within the accumulator — MSB-first vs LSB-first.

Recover both from the decompiled unpacker's shift direction:
`(acc >> (bits - width))` masked = **MSB-first**; `(acc >> consumed) & mask` =
**LSB-first**. Don't guess — read the shift. Port it exactly:

```python
class BitReader:            # MSB-first, matches (acc >> (n-width)) & mask
    def __init__(self, buf): self.buf, self.pos = buf, 0
    def read(self, width):
        v = 0
        for _ in range(width):
            byte = self.buf[self.pos >> 3]
            bit  = (byte >> (7 - (self.pos & 7))) & 1
            v = (v << 1) | bit
            self.pos += 1
        return v
```

## Verify layout against the app before trusting values

You cannot eyeball-verify a packed blob. Use the app-as-oracle (see
`native-oracle-validation.md` §1b): drive a real sample through the app's own
decoder, read its decoded struct field-for-field, and diff against your port.
This catches the subtle ones — a trailing padding space on a fixed-width text
column, a signed-vs-unsigned angle, an off-by-one in record_count.

## Compression wrapper: identify wbits from the header bytes, don't assume

If the column blob is compressed, the raw-vs-zlib-vs-gzip choice (and the zlib
`wbits` window) is part of the format. `78 9c`/`78 01`/`78 da` = zlib w/ header;
`1f 8b` = gzip; no recognizable header = raw DEFLATE (`wbits = -15`). When you
lack a real sample to confirm, leave it as an explicit OPEN ITEM in the spec doc
rather than hardcoding a guess — the wrong wbits fails silently on some inputs.

## Deliverable

Write a `FPC6_FORMAT_SPEC.md`-style doc: magic/version, descriptor struct with
byte offsets, per-column type semantics, bit-field layouts with fill order, and
an explicit OPEN ITEMS list for anything a real sample hasn't yet pinned down
(compression wbits, ambiguous enum columns). Anchor every claim to the
decompiled function address it came from.
