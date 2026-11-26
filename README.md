# chinese_codec

[简体中文](https://github.com/bigedev/chinese_codec/blob/main/README.cn.md) | **English**

Pure Dart codecs for Chinese charsets: **GB18030** (including its 4-byte form and the
supplementary planes), **GBK**, **GB2312**, **Big5** (CP950) and **Big5-HKSCS** (Hong Kong
Supplementary Character Set). No native dependencies, no FFI — works on servers, CLIs and
Flutter (HarmonyOS / Android included).

## Why

`dart:convert` ships UTF-8, Latin-1 and ASCII only. Legacy files written in GBK or Big5
(Visual Basic, Delphi, source code and configs from early Windows) either end in a
`FormatException` or — worse — get read as Latin-1 and turn into garbage without any
error at all.

## Install

```bash
dart pub add chinese_codec
```

The command writes the dependency into `pubspec.yaml` and fills in the constraint from the
latest version on pub.dev. Adding it by hand works too: list `chinese_codec` under
`dependencies` and pick the constraint your project needs.

It works right after `dart pub get`; in a Flutter project (HarmonyOS / Android / iOS) it is
just an ordinary dependency with no extra setup.

## Usage

### Basic decoding and encoding

```dart
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

All five codecs extend `Encoding` (`Encoding` itself is re-exported by this package, so writing
`List<Encoding>` needs no `import 'dart:convert'`), so they can be passed straight to
`File.readAsString(encoding:)` / `File.writeAsString(encoding:)`:

```dart
import 'dart:io';

final String text = File('legacy.bas').readAsStringSync(encoding: gbk);
File('legacy.utf8.bas').writeAsStringSync(text);  // written back as UTF-8
```

### Files and streams

For files too large to hold in memory, decode them as a stream. This is **genuinely
incremental**: text is handed over as each chunk arrives, and only the 1–3 trailing bytes that
cannot be decided yet are held back (the two bytes of a Chinese character, or a GB18030
four-byte sequence, may well straddle two chunks):

```dart
final String text = await gbk.decodeStream(file.openRead());
// the same, written as a transform — handy to attach to another Stream, or to map / filter
final String same = await file.openRead().transform(gbk.decoder).join();
```

The result is character-for-character identical to `decode(wholeFile)`, and memory holds only
those trailing bytes. In strict mode a bad byte may surface mid-stream: everything decoded
before it is delivered — including the part of the failing chunk that precedes the bad byte —
and it always stops on a character boundary, never half a character. After the error the stream
yields no further text, and `FormatException.offset` is a byte offset into the whole stream.

### Reading unclean data

When reading *something* matters more than strictness, pass `allowInvalid` (bad bytes become
U+FFFD, the same as `utf8` with `allowMalformed`):

```dart
const GbkCodec lenient = GbkCodec(allowInvalid: true);
final String text = lenient.decode(bytes);  // invalid bytes → U+FFFD
```

Reading *something* **and** knowing where it went wrong — `decodeLossy` reports the offset
of every byte it had to replace:

```dart
final DecodeReport report = GbkCodec().decodeLossy(bytes);
if (!report.isClean) {
  print('${report.lostBytes} bytes lost at ${report.lostOffsets}');
  // e.g. "2 bytes lost at [1, 3]" — every U+FFFD in report.text has a matching offset
}
```

### Lookup by name

Knows aliases such as `CP936`, `EUC-CN` and `CP950` — handy for MIME types and git config. The
lookup is case-insensitive and trims surrounding whitespace:

```dart
chineseEncodingByName('cp936');      // → gbk (a GbkCodec)
chineseEncodingByName('euc-cn');     // → gb2312
chineseEncodingByName('cp950');      // → big5
chineseEncodingByName('big5-hkscs'); // → big5hkscs
chineseEncodingByName('shift_jis');  // → null (unknown encoding)

identical(chineseEncodingByName(' cp936 '), gbk);  // true — shared instances, safe to compare
```

## Coverage

| Encoding | Single byte | Double byte | Four byte | Notes |
|---|---|---|---|---|
| GB2312 | ASCII | ✓ (7,445 characters) | ✗ | The oldest national standard, a strict subset of GBK |
| GBK (CP936) | ASCII | ✓ (21,791 characters) | ✗ | The most common Simplified Chinese on Windows |
| GB18030 | ASCII | ✓ (23,940 characters, including the user-defined area GBK rejects) | ✓ | Fills in the BMP + U+10000..U+10FFFF |
| Big5 (CP950) | ASCII | ✓ (13,742 characters) | ✗ | Traditional Chinese; the most common on Windows |
| Big5-HKSCS | ASCII | ✓ (18,494 characters, including all 13,742 of CP950) | ✗ | Traditional Chinese; HKSCS, includes 1,713 supplementary-plane code points |

The counts are **characters**: a character that occupies several byte pairs counts once (the 10
duplicate byte pairs in Big5 such as `十` / `卅`), while the four Big5-HKSCS combining characters
put two characters in one byte pair — so its 18,594 byte pairs correspond to 18,494 characters.
"Cell", used later when describing the tables, means the double-byte position itself.

Suggested order: **try UTF-8 first, then a Chinese codec confirmed by a round trip**.
A wide encoding that *can* decode a byte sequence has not necessarily decoded it
*correctly* — random bytes may still come out as rare characters (or as valid ones).

```dart
import 'dart:convert';  // only for utf8; the Chinese codecs come from this package

String readLegacy(List<int> bytes) {
  final String? utf8Text = tryDecode(bytes, utf8);
  if (utf8Text != null) return utf8Text;

  final List<Encoding> fits = codecsThatRoundTrip(bytes);
  // 0 candidates: neither UTF-8 nor any Chinese charset (truncated / binary / other)
  // 1 candidate : that is your answer (GB18030 four-byte sequences land here)
  // several     : the byte spaces overlap — the call is yours; this takes the first
  //               in chineseCodecs order
  if (fits.isEmpty) {
    throw const FormatException('neither UTF-8 nor any Chinese charset');
  }
  return fits.first.decode(bytes);
}
```

`codecsThatRoundTrip` is **evidence, not a guess**: it reports which encodings decode the
bytes *and* re-encode them back to the same bytes. Two things it deliberately does not do:

- It does **not** tell Simplified from Traditional. The GBK bytes of `中文` round-trip
  cleanly as Big5 too (they come out as `笢恅`), so all five codecs can pass on ordinary
  Simplified text. What narrows the list down is GB2312 running out of cells, GB18030's
  four-byte sequences, or a file that is not text at all.
- It does **not** score candidates by character frequency. That is a heuristic, and a wrong
  guess is harder to debug than an error, so the decision stays with the caller.

Before writing a file, check whether the target charset can hold the text at all —
`encode` throws on the *first* character it cannot represent, `unrepresentableRunes`
lists every one of them:

```dart
final List<int> missing = unrepresentableRunes(text, gb2312);
if (missing.isNotEmpty) {
  print('GB2312 cannot store: ${missing.map(String.fromCharCode).join()}');
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
  code points. On the cross-check: all 13,752 cells match CPython's `cp950` exactly, while
  macOS `iconv`'s CP950 does not accept the 249 ETen extension cells (`0xC6A1`-`0xC7FE`, kana /
  Cyrillic / Greek) — the remaining 13,503 cells match this package cell for cell. Expectation
  values should not be taken from CPython's `big5`, which uses the old BIG5.TXT table.
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
- Of the 18,594 Big5-HKSCS cells, **all 18,402** of CPython's `big5hkscs` are included; this
  package has 192 more (`0xA3E1`'s "€", `0x877B`'s U+21D53 and other characters added after
  HKSCS-2008). Data sources are listed in the last section.
- Two GB2312 cells map to different code points than GBK / GB18030 (a historical leftover):
  `0xA1A4` is "・" (U+30FB) and `0xA1AA` is "―" (U+2015). `U+00B7` is therefore not
  representable in GB2312 — an inconsistency of the standard itself, not a deviation of this
  package.
- No encoding **detection**, only evidence: `tryDecode` / `verifyRoundTrip` /
  `codecsThatRoundTrip` say which encodings *can* explain a byte sequence; nothing ranks them
  or picks one (the reasoning is under Coverage above).

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
single encoding only pays for that one. Decode throughput (AOT, 1 MB corpus, 8 KB chunks) is
around 96 MB/s for GBK — every table runs through the same `writeCharCode` hot path.

Always run `dart test` after touching the generator: the tests round-trip **every cell**
(counted in byte pairs, duplicates included: GBK 21,791, GB2312 7,445, GB18030 23,940
double-byte + 39,420 BMP four-byte, Big5 13,752, Big5-HKSCS 18,594), which catches a single
wrong bit.

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
