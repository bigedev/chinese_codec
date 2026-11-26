# Changelog

[简体中文](https://github.com/bigedev/chinese_codec/blob/main/CHANGELOG.cn.md) | **English**

## 0.1.4

Documentation and example only — no API, mapping or behaviour changes. Upgrade to get the docs.

- **An `Install` section.** `dart pub add chinese_codec`, plus the reminder that a Flutter project
  needs nothing beyond the dependency.
- **A snippet that could not compile is fixed.** The "try UTF-8, then a Chinese codec" example
  was a bare `return` at top level; it is now a complete `readLegacy(bytes)` function.
- **Usage is split into subsections** — basic decoding/encoding, files and streams, reading
  unclean data, lookup by name — so the page can be navigated instead of scrolled.
- **Coverage counts are now characters, not cells**: Big5 13,742 and Big5-HKSCS 18,494, because
  ten Big5 cells duplicate a character and the four HKSCS combining characters put two
  characters in one cell. GBK 21,791 / GB2312 7,445 / GB18030 23,940 are unchanged.
- **Duplicated passages removed** (incremental decoding, "no detection", HKSCS data sources) and
  the README no longer pins a version number, so it stays correct across releases.
- **Cross-check wording corrected**: Big5 matches CPython's `cp950` on all 13,752 cells, but
  macOS `iconv`'s CP950 does not accept the 249 ETen extension cells — so the docs now state
  the 13,503-cell intersection instead of claiming a full match with both references.
- **The example now shows the error side**: strict `FormatException` with its byte offset,
  `allowInvalid`, the CP950-vs-HKSCS cell conflict (`0xC6A1` → ヾ / ①), writing and re-reading a
  GBK file, and chunked encoding of a surrogate pair split across two chunks.

## 0.1.3

- **Four helpers for the "what encoding is this file?" question** — the answer is evidence,
  not a guess:
  - `tryDecode(bytes, encoding)` decodes strictly and returns `null` instead of throwing;
  - `verifyRoundTrip(bytes, encoding)` checks that decoding and re-encoding gives back the
    same bytes;
  - `codecsThatRoundTrip(bytes)` lists every candidate that passes — **0** means "not UTF-8
    and not any Chinese charset", **1** is your answer, **several** means the byte spaces
    overlap. Documented honestly: the GBK bytes of `中文` round-trip as Big5 too (`笢恅`),
    so this cannot tell Simplified from Traditional — the package still never guesses.
  - `unrepresentableRunes(text, encoding)` lists **every** character the target charset
    cannot store; `encode` only reports the first one.
- **`decodeLossy` on all five codecs**: lenient decoding that also says where it lost data.
  Returns a `DecodeReport` with `text`, `lostOffsets` (ascending byte offsets) and
  `lostBytes`; every U+FFFD in the text has a matching offset. It ignores `allowInvalid` —
  a report only makes sense when decoding is lenient.
- **Streaming decode is genuinely incremental now**: `decodeStream(...)`, `decoder.bind(...)`
  and `stream.transform(codec.decoder)` emit text as each chunk arrives instead of reading the
  whole stream first. Only the 1–3 trailing bytes that cannot be decided yet are held back
  (up to three for the GB18030 four-byte form). Measured with 8 KB chunks: 74 → 96 MB/s (AOT,
  1 MB corpus), and a large file no longer has to fit in memory. In strict mode a bad byte can
  now surface mid-stream: everything decoded before it — including the part of the failing
  chunk that precedes the bad byte — is still delivered, and the stream produces no text after
  the error. (Upstream is not cancelled on error, and continuing would stitch the stale held
  bytes into characters that were never there.)
- **Streaming decode reports offsets into the whole stream.** They used to be offsets into the
  input being decoded; a stream has no single such input, so `FormatException.source` is empty.
- **Encoding no longer chokes on a character whose two code units are split across chunks** —
  the surrogate pair of a supplementary-plane character, and the four Big5-HKSCS combining
  characters (`0x8862` → U+00CA U+0304 occupies one cell but two code points).
  `stream.transform(codec.encoder)` used to throw "not representable" when the halves landed in
  different chunks. It now holds the first half until the second arrives; if the stream ends
  with only the first half, it still throws.
- `example/` grew from a set of one-liners into a walkthrough: unknown bytes → candidate
  encodings → loss report → export check.

## 0.1.2

- **Big5-HKSCS encoding used to pick the HKSCS extension cell** whenever a character also had
  a regular Big5 cell: `兙` came out as `0x92AF`, which CP950 / Windows cannot decode. Encoding
  now prefers the standard Big5 block (lead `0xA1`–`0xF9`) — that character is `0xA259` again.
  56 code points were affected; decoding is unchanged.
- **Big5 / Big5-HKSCS encoding now writes the canonical cell** for the two characters that
  CP950 maps twice: `十` → `0xA451`, `卅` → `0xA4CA` (what Windows, iconv's CP950 and CPython
  emit) instead of `0xA2CC` / `0xA2CE`. Decoding either cell still works.
- **Chunked conversion now works**: `codec.decoder.bind(...)`, `codec.encoder.bind(...)` and
  `stream.transform(codec.decoder)` used to throw `UnsupportedError`. Decoding buffers the
  whole stream (a multi-byte character may straddle two chunks); encoding converts per chunk.
- **Decoding is 2–3× faster, GB18030 encoding up to 8×**: the decoder no longer allocates a
  single-character `String` per decoded character, the GB18030 encoder no longer writes byte by
  byte through `BytesBuilder`, and the reverse lookup tables are a `Uint16List` instead of a
  hash map (GBK cold start 2.7 ms → 0.13 ms; up to 1.7 MB → 128 KB per encoding).
- `chineseEncodingByName` trims surrounding whitespace and knows more aliases: `GB-2312`,
  `CP-936`, `CP-950`, `X-GBK`, `GB18030-2000`, `GB18030-2022`.
- `Encoding` from `dart:convert` is re-exported, so `List<Encoding>` no longer needs a second
  import.
- Documented the 11 punctuation cells where Big5 follows Windows CP950 but CPython's `big5`
  does not, and the 11 cells where Big5-HKSCS follows WHATWG but glibc / CPython do not.

## 0.1.1

- Filled in the API documentation on pub.dev: the constructors of all five codecs plus
  `name` / `layout` / `encoder` / `decoder` / `decodeStream` / `toString` now spell out their
  values and behaviour instead of showing a bare signature. It also states that
  `allowInvalid` **affects decoding only** — characters that cannot be encoded always throw
  `FormatException`.
- Fixed `decodeStream`: `Converter` does not implement chunked conversion, so the default
  implementation in `dart:convert` threw `UnsupportedError` on the first call. It now reads
  the whole byte stream before decoding, so multi-byte characters split across two chunks
  decode correctly.

## 0.1.0

- First release: encode/decode for GB18030 (1 / 2 / 4 bytes, including the supplementary
  plane linear area), GBK, GB2312, Big5 (CP950) and Big5-HKSCS.
- GB18030 follows the **2022 edition**: the 19 code point swaps of Annex D, Table D.1 (10
  vertical punctuation marks, 8 Han components, U+1E3F ⇄ PUA U+E7C7), aligned entry by entry
  with ICU's `gb18030-2022.ucm`.
- The three GB encodings share one GB18030 double-byte table; GBK / GB2312 differences are
  expressed as validity bitmaps plus 2 overrides.
- New **Big5-HKSCS**: 18,594 cells, including 1,713 supplementary-plane code points
  (Cantonese, personal and place names). Data comes from WHATWG Encoding Standard's
  `index-big5.txt` (Big5 + HKSCS-2008) and was cross-checked against CPython's `big5hkscs`.
  - **Not a superset relationship** with Big5 (CP950): the cells are a superset of CP950, but
    250 cells map differently (HKSCS repurposed the ETen extension area of kana, Cyrillic and
    Greek, so `0xC6A1` is "①" rather than "ヾ"). The encoding has to follow the source file.
  - 4 cells are combining characters — "one byte pair, two code points" (`0x8862` →
    U+00CA U+0304). Both directions handle the two code points as a unit, so round trips
    hold.
- `allowInvalid` means the same as `utf8.decode(allowMalformed:)`: invalid bytes become
  U+FFFD instead of throwing.
- `chineseCodecs` / `chineseEncodingByName()` look encodings up by name (knowing aliases such
  as CP936, EUC-CN and Big5-HKSCS).
