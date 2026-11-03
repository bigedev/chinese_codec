# Changelog

[简体中文](CHANGELOG.cn.md) | **English**

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
