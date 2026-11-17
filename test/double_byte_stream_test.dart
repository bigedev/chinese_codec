import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

import 'stream_support.dart';

/// 遍历一段首字节 × 次字节空间，逐格比较「切在两块里」与「整段」。
///
/// 返回（不一致的格子，严格模式下有效的格子数，解出两个 UTF-16 单元的格子数）。
({List<String> bad, int valid, int twoUnit}) _scanCells(
  Encoding strict,
  Encoding lenient, {
  required int leadMin,
  required int leadMax,
  bool Function(int trail)? trailAllowed,
}) {
  final List<String> bad = <String>[];
  int valid = 0;
  int twoUnit = 0;
  for (int lead = leadMin; lead <= leadMax; lead++) {
    for (int trail = 0x00; trail <= 0xFF; trail++) {
      if (trailAllowed != null && !trailAllowed(trail)) continue;
      final List<int> bytes = <int>[lead, trail];
      final String whole = wholeResult(strict, bytes);
      for (final Encoding codec in <Encoding>[strict, lenient]) {
        final String expected =
            identical(codec, strict) ? whole : wholeResult(codec, bytes);
        final String chunked = chunkedPair(codec, lead, trail);
        if (chunked != expected) {
          bad.add('${codec.name} ${hexByte(lead)} ${hexByte(trail)}: '
              '$expected vs $chunked');
        }
      }
      if (whole.startsWith('ok:')) {
        valid++;
        // 'ok:' + 两个 code unit ⇒ 一格出两个 UTF-16 单元
        if (whole.length == 'ok:'.length + 2) twoUnit++;
      }
    }
  }
  return (bad: bad, valid: valid, twoUnit: twoUnit);
}

void main() {
  // 每个格子都切在字节对中间跑一遍。分块解码只有一条共享循环，所以这里除了抓「切点
  // 处理」本身的错，也顺带证明各编码的 layout（哪些首字节/次字节合法）在流式下没走样。
  group('逐格切在字节对中间', () {
    test('Big5：13,752 个有效格', () {
      final ({List<String> bad, int valid, int twoUnit}) result = _scanCells(
        big5,
        const Big5Codec(allowInvalid: true),
        leadMin: 0x80,
        leadMax: 0xFE,
      );
      expect(result.bad, isEmpty, reason: result.bad.take(10).join('; '));
      // 与 big5_test.dart 的全量往返数一致：说明真把每个有效格都切过
      expect(result.valid, 13752);
    });

    test('Big5-HKSCS：18,594 个有效格，其中 1,717 个两单元格', () {
      final ({List<String> bad, int valid, int twoUnit}) result = _scanCells(
        big5hkscs,
        const Big5HkscsCodec(allowInvalid: true),
        leadMin: 0x87,
        leadMax: 0xFE,
        trailAllowed: (int trail) =>
            trail != 0x7F && (trail <= 0x7E || trail >= 0xA1),
      );
      expect(result.bad, isEmpty, reason: result.bad.take(10).join('; '));
      expect(result.valid, 18594);
      // 1,713 个补充平面字符（解码出代理对）+ 4 个组合字符（一格两个码位）
      expect(result.twoUnit, 1717);
    });

    test('GBK：21,791 个有效格', () {
      final ({List<String> bad, int valid, int twoUnit}) result = _scanCells(
        gbk,
        const GbkCodec(allowInvalid: true),
        leadMin: 0x80,
        leadMax: 0xFE,
      );
      expect(result.bad, isEmpty, reason: result.bad.take(10).join('; '));
      expect(result.valid, 21791);
    });

    test('GB2312：7,445 个有效格', () {
      final ({List<String> bad, int valid, int twoUnit}) result = _scanCells(
        gb2312,
        const Gb2312Codec(allowInvalid: true),
        leadMin: 0x80,
        leadMax: 0xFE,
      );
      expect(result.bad, isEmpty, reason: result.bad.take(10).join('; '));
      expect(result.valid, 7445);
    });

    test('GB18030 双字节区：23,940 个有效格（含 GBK 不收的用户自定义区）', () {
      final ({List<String> bad, int valid, int twoUnit}) result = _scanCells(
        gb18030,
        const Gb18030Codec(allowInvalid: true),
        leadMin: 0x80,
        leadMax: 0xFE,
      );
      expect(result.bad, isEmpty, reason: result.bad.take(10).join('; '));
      expect(result.valid, 23940);
    });
  });

  test('GB18030 四字节形式：抽样序列 × 三个切点', () {
    // 四字节索引空间有 189,000 个（BMP 部分），逐个跑太慢；每 37 个抽一个，
    // 三个位置各切一刀 —— 首字节/第二字节/第三字节后面都可能断，四种坏组合也都在样本里。
    final List<String> bad = <String>[];
    int checked = 0;
    for (int index = 0; index < 189000; index += 37) {
      final List<int> four = <int>[
        0x81 + index ~/ 12600,
        0x30 + (index % 12600) ~/ 1260,
        0x81 + (index % 1260) ~/ 10,
        0x30 + index % 10,
      ];
      for (final Encoding codec in <Encoding>[
        gb18030,
        const Gb18030Codec(allowInvalid: true),
      ]) {
        final String whole = wholeResult(codec, four);
        for (int cut = 1; cut < 4; cut++) {
          final String chunked = chunkedResult(codec, <List<int>>[
            four.sublist(0, cut),
            four.sublist(cut),
          ]);
          checked++;
          if (chunked != whole) {
            bad.add('${codec.name} $four cut=$cut: $whole vs $chunked');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: bad.take(10).join('; '));
    expect(checked, greaterThan(30000));
  });

  group('Big5 系专有的边界', () {
    test('补充平面：切在两块里仍然是一个字', () {
      // 0x9DB7 是 HKSCS 里的 U+23CB7，解码要出代理对。
      // 注意 ASCII 的 0x41 也是合法第二字节，所以「后面跟个 A」要整块跟在格子之后。
      const List<List<List<int>>> cases = <List<List<int>>>[
        <List<int>>[
          <int>[0x9d],
          <int>[0xb7],
        ],
        <List<int>>[
          <int>[0x9d],
          <int>[0xb7, 0x41],
        ],
        <List<int>>[
          <int>[0x9d],
          <int>[],
          <int>[0xb7],
        ],
      ];
      const List<String> expected = <String>[
        '\u{23CB7}',
        '\u{23CB7}A',
        '\u{23CB7}',
      ];
      for (int i = 0; i < cases.length; i++) {
        expect(chunkedResult(big5hkscs, cases[i]), 'ok:${expected[i]}');
      }
    });

    test('4 个组合字符：解码 / 编码 / 跨块都一致', () async {
      // 一格两个码位：字节对 → 两个码位；反过来也要按这两个码位整体匹配
      const Map<int, String> combining = <int, String>{
        0x8862: '\u00CA\u0304',
        0x8864: '\u00CA\u030C',
        0x88A3: '\u00EA\u0304',
        0x88A5: '\u00EA\u030C',
      };
      for (final MapEntry<int, String> entry in combining.entries) {
        final int cell = entry.key;
        final String text = entry.value;
        final String reason = hexByte(cell);
        final List<int> bytes = <int>[cell >> 8, cell & 0xFF];

        expect(big5hkscs.decode(bytes), text, reason: reason);
        expect(chunkedPair(big5hkscs, bytes[0], bytes[1]), 'ok:$text',
            reason: reason);
        expect(big5hkscs.encode(text), bytes, reason: reason);

        // 编码方向切在两个码位之间：不能只编前一半
        final List<int> encoded = await big5hkscs.encoder
            .bind(Stream<String>.fromIterable(<String>[
              text.substring(0, 1),
              text.substring(1),
            ]))
            .expand((List<int> chunk) => chunk)
            .toList();
        expect(encoded, bytes, reason: reason);
      }
    });

    test('首字节判定：Big5 立刻判死，HKSCS 要等下一块', () {
      const Big5Codec lenient = Big5Codec(allowInvalid: true);
      // 0xA0 不在 0xA1-0xF9；0xFA-0xFE 是 CP950 的用户自定义区；0x87 / 0x9D 是 HKSCS 扩展区
      for (final int lead in <int>[0x80, 0x87, 0x9d, 0xa0, 0xfa, 0xfe]) {
        expect(chunkedPair(lenient, lead, 0x40), 'ok:\uFFFD@',
            reason: hexByte(lead));
      }
      // 同样的 0x8740 在 HKSCS 里是扩展区的 CJK 字符 —— 说明它把首字节留到了下一块
      expect(big5hkscs.decode(<int>[0x87, 0x40]), '\u43F0');
      expect(chunkedPair(big5hkscs, 0x87, 0x40), 'ok:\u43F0');
    });

    test('非法第二字节（0x7F / 0x80 / 0xA0）跨块与整段一致', () {
      const Big5Codec lenient = Big5Codec(allowInvalid: true);
      for (final int trail in <int>[0x7f, 0x80, 0xa0]) {
        expect(
          chunkedPair(lenient, 0xa4, trail),
          wholeResult(lenient, <int>[0xa4, trail]),
          reason: hexByte(trail),
        );
      }
    });
  });
}
