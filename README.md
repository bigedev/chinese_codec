# chinese_codec

[简体中文](https://atomgit.com/eltoro/chinese_codec/blob/main/README.cn.md) | **English**

Pure Dart codecs for Chinese charsets: **GB18030** (including its 4-byte form and the
supplementary planes), **GBK**, **GB2312**, **Big5** (CP950) and **Big5-HKSCS** (Hong Kong
Supplementary Character Set). No native dependencies, no FFI — works on servers, CLIs and
Flutter (HarmonyOS / Android included).

## Why

`dart:convert` ships UTF-8, Latin-1 and ASCII only. Legacy files written in GBK or Big5
(Visual Basic, Delphi, source code and configs from early Windows) either end in a
`FormatException` or — worse — get read as Latin-1 and turn into garbage without any
error at all.

## Usage

```dart
import 'dart:convert';
import 'package:chinese_codec/chinese_codec.dart';

void main() {
  final List<int> bytes = <int>[0xd6, 0xd0, 0xce, 0xc4];

  print(gbk.decode(bytes));      // 中文 (Simplified)
  print(gb2312.decode(bytes));   // 中文 (subset, decodes the same)
  print(gb18030.decode(bytes));  // 中文
  print(big5.decode(<int>[0xa4, 0xa4, 0xa4, 0xe5]));  // 中文 (Traditional)
  print(big5hkscs.decode(<int>[0x9d, 0xb7]));         // 𣲷 (Hong Kong; CP950 misses it)

  print(gbk.encode('中文'));      // [214, 208, 206, 196]
}
```

All five codecs extend `Encoding`, so they can be passed straight to
`File.readAsString(encoding:)` / `File.writeAsString(encoding:)`:

```dart
final String text = File('legacy.bas').readAsStringSync(encoding: gbk);
File('legacy.utf8.bas').writeAsStringSync(text);  // written back as UTF-8
```

When the content looks unclean and reading *something* matters more than strictness:

```dart
const GbkCodec lenient = GbkCodec(allowInvalid: true);
final String text = lenient.decode(bytes);  // invalid bytes → U+FFFD, same as utf8 allowMalformed
```

Lookups by name (knows aliases such as `CP936`, `EUC-CN`, `CP950` — handy for MIME types and
git config):

```dart
chineseEncodingByName('cp936');      // GbkCodec
chineseEncodingByName('euc-cn');     // Gb2312Codec
chineseEncodingByName('cp950');      // Big5Codec
chineseEncodingByName('big5-hkscs'); // Big5HkscsCodec
```

## Coverage

| Encoding | Single byte | Double byte | Four byte | Notes |
|---|---|---|---|---|
| GB2312 | ASCII | ✓ (7,445 characters) | ✗ | The oldest national standard, a strict subset of GBK |
| GBK (CP936) | ASCII | ✓ (21,791 cells) | ✗ | The most common Simplified Chinese on Windows |
| GB18030 | ASCII | ✓ (23,940 cells, including the user-defined area GBK rejects) | ✓ | Fills in the BMP + U+10000..U+10FFFF |
| Big5 (CP950) | ASCII | ✓ (13,752 cells) | ✗ | Traditional Chinese; the most common on Windows |
| Big5-HKSCS | ASCII | ✓ (18,594 cells, including all 13,752 of CP950) | ✗ | Traditional Chinese; HKSCS, includes 1,713 supplementary-plane code points |

Suggested detection order: **try UTF-8 first, then GB18030 (Simplified) / Big5 or Big5-HKSCS
(Traditional)**. A wide encoding that *can* decode a byte sequence has not necessarily
decoded it *correctly* — random bytes may still come out as rare characters. For more
confidence, verify a round trip:

```dart
final String text = gb18030.decode(bytes);
if (gb18030.encode(text).toString() == bytes.toString()) {
  // round trip matches, the guess is probably right
}
```

## Known limitations

- **GB18030 follows the 2022 edition** (the 19 swap groups of Annex D, Table D.1): 10 vertical
  punctuation marks (from `A6D9`), 8 Han components (from `FE59`) and the `A8BC` group have
  their code points exchanged between the double-byte cells and the four-byte sequences.
  The same bytes may therefore decode to a "real character" here and to a PUA code point
  under CPython (2000 / 2005 editions) — that is the standard changing, not a bug.
  - One **deliberate divergence** from **ICU**'s `gb18030-2022.ucm`: ICU marks those 18
    four-byte sequences as ignored (they fail to decode in legacy files), while this package
    performs the full national-standard swap and still yields the original PUA code points,
    keeping round trips intact.
  - Tables D.2 (6 components) and D.3 (9 CJK compatibility ideographs) only affect **glyphs
    and charset membership**, not the "bytes ↔ code points" mapping (ICU's 2022 data also
    keeps mappings such as `FD9C` → U+F92C), so this package is unaffected.
- **Big5 means CP950** here (the de facto ceiling of Traditional Chinese on Windows): 42 cells
  more than classic Big5 (for example `0xA3E1` is "€"), plus 11 cells mapping to different
  code points.
- **Big5-HKSCS is not a superset relationship**: its cells are a superset of CP950 (all 13,752
  cells are present), but **250 cells map differently** — HKSCS repurposes the ETen extension
  area of kana, Cyrillic and Greek (`0xC6A1`-`0xC8FE` and friends) for Han characters and
  circled numbers, so `0xC6A1` is "ヾ" under CP950 but "①" under HKSCS. Read Traditional
  Chinese files saved on Windows with `big5`, and Hong Kong HKSCS files (Cantonese, personal
  and place names) with `big5hkscs`. Picking the wrong one **raises no error** — only a few
  characters come out wrong. That is exactly why the encoding has to follow the source rather
  than "whichever covers more".
- Big5-HKSCS has 4 cells that are combining characters — "one byte pair, two code points"
  (`0x8862` → U+00CA + U+0304, accented Latin letters of that kind): decoding yields two
  characters, and encoding matches the pair of code points as a whole and produces the same
  cell. So "character count == byte count / 2" does not hold for such text.
- Big5-HKSCS data comes from WHATWG's `index-big5.txt` (Big5 + HKSCS-2008, 18,590 cells) plus
  the 4 combining characters defined separately in the specification body, 18,594 cells in
  total. CPython's `big5hkscs` has 18,402 cells, **all of them included here**; this package
  has 192 more (`0xA3E1`'s "€", `0x877B`'s U+21D53 and other characters added after
  HKSCS-2008).
- Two GB2312 cells map to different code points than GBK / GB18030 (a historical leftover):
  `0xA1A4` is "・" (U+30FB) and `0xA1AA` is "―" (U+2015). `U+00B7` is therefore not
  representable in GB2312 — an inconsistency of the standard itself, not a deviation of this
  package.
- No encoding **detection**: given a byte sequence, the package will not guess "GBK or Big5?".
  A wrong guess is harder to debug than an error, so detection is left to the caller (see
  "UTF-8 first, then the matching codec + round-trip check" above).

## Implementation and size

The mapping tables are generated by `tool/gen_tables.py` from the "code point ↔ bytes" facts
alone; no third-party implementation code is included:

- GB family and Big5: read from CPython's `gbk` / `gb18030` / `gb2312` / `cp950` codecs; the
  four-byte area is additionally adjusted per GB 18030—2022 Annex D (see the limitations
  above).
- Big5-HKSCS: read from WHATWG's `index-big5.txt` (Big5 + HKSCS-2008), downloaded with
  SHA-256 verification and cached under `tool/.cache/`; then cross-checked cell by cell
  against CPython's `big5hkscs`.

Table layout:

- GB family: one GB18030 double-byte table (23,940 entries) + two validity bitmaps (which
  cells GBK / GB2312 accept) + 2 overrides; the four-byte BMP area is compressed into 221
  contiguous runs, and the supplementary planes use a linear formula (no table needed).
- Big5: one table of 13,973 cells (13,752 valid).
- Big5-HKSCS: one table of 18,840 cells (18,594 valid); the BMP part is looked up directly.
  The 1,717 cells that emit two UTF-16 units (1,713 supplementary-plane characters + 4
  combining characters) carry a 0xFFFF sentinel in the main table and fall through to an
  auxiliary table. Reverse maps are built lazily on first encode.

The generated output is about 192 KB of source (`tables.g.dart` 123 KB +
`tables_big5hkscs.g.dart` 69 KB); each table is decoded lazily on first use, so adopting a
single encoding only pays for that one.

Always run `dart test` after touching the generator: the tests round-trip **every cell**
(GBK 21,791, GB2312 7,445, GB18030 23,940 double-byte + 39,420 BMP four-byte, Big5 13,752,
Big5-HKSCS 18,594), which catches a single wrong bit.

## Data sources and license

- The package itself: MIT (see [LICENSE](LICENSE)).
- Mapping data derives from Unicode's official CP936 / CP950 mapping tables, the GB 2312
  standard, and the cross-check of **GB 18030—2022 Annex D** (the 2022 swaps) against ICU's
  `gb18030-2022.ucm`. It is factual data; this project is distributed under MIT and contains
  no third-party implementation code.
- Big5-HKSCS mappings come from the **WHATWG Encoding Standard**'s `index-big5.txt`
  (Big5 + HKSCS-2008; the specification is published under CC BY 4.0). Again only the
  factual "bytes ↔ code points" layer is used — no specification prose and no implementation
  code. The values of the four combining characters come from the "Pointer / Code points"
  table in the specification body.
- `A3A0` → U+E5E5 (PUA) is kept: ICU's 2022 table does not have that cell, but the 2005
  edition and most implementations still map it, and dropping it would only break legacy
  files — the costs are asymmetric.
