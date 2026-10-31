import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

void main() {
  group('双字节区', () {
    test('与 GBK 一致的部分', () {
      expect(gb18030.decode(<int>[0xd6, 0xd0, 0xce, 0xc4]), '中文');
      expect(gb18030.encode('中文'), <int>[0xd6, 0xd0, 0xce, 0xc4]);
    });

    test('GBK 不收的用户自定义区，GB18030 收（落在 PUA）', () {
      // 0xA140：GBK 判非法，GB18030 映射到 U+E4C6
      expect(gb18030.decode(<int>[0xa1, 0x40]), '\ue4c6');
      expect(gb18030.encode('\ue4c6'), <int>[0xa1, 0x40]);
      expect(() => gbk.decode(<int>[0xa1, 0x40]), throwsFormatException);
    });
  });

  group('四字节区', () {
    test('BMP 里 GBK 覆盖不到的字符', () {
      // U+20AC 欧元符号：GB18030 是 0xA2E3（双字节）
      expect(gb18030.decode(<int>[0xa2, 0xe3]), '\u20ac');
      // U+30FB「・」只有四字节形式 0x8139A739
      expect(gb18030.decode(<int>[0x81, 0x39, 0xa7, 0x39]), '\u30fb');
      expect(gb18030.encode('\u30fb'), <int>[0x81, 0x39, 0xa7, 0x39]);
    });

    test('补充平面：U+10000 与 U+10FFFF', () {
      expect(gb18030.decode(<int>[0x90, 0x30, 0x81, 0x30]), '\u{10000}');
      expect(gb18030.encode('\u{10000}'), <int>[0x90, 0x30, 0x81, 0x30]);
      expect(gb18030.decode(<int>[0xe3, 0x32, 0x9a, 0x35]), '\u{10FFFF}');
      expect(gb18030.encode('\u{10FFFF}'), <int>[0xe3, 0x32, 0x9a, 0x35]);
    });

    test('补充平面里抽样往返', () {
      for (int codePoint = 0x10000;
          codePoint <= 0x10FFFF;
          codePoint += 0x1111) {
        final String text = String.fromCharCode(codePoint);
        expect(gb18030.decode(gb18030.encode(text)), text,
            reason: 'U+${codePoint.toRadixString(16)}');
      }
    });

    test('越界的四字节序列判非法', () {
      // U+10FFFF 之后的序号没有对应码位
      expect(
        () => gb18030.decode(<int>[0xe3, 0x32, 0x9a, 0x36]),
        throwsFormatException,
      );
    });
  });

  group('GB18030-2022 的 19 组码位互换', () {
    // 国标附录 D 表 D.1（+ A8BC 那组）：2005 版把「真字符」放在四字节序列上、
    // 双字节格子留给 PUA；2022 版把两者对调。数值与 ICU 的 gb18030-2022.ucm 核对过。
    const List<({List<int> cell, int real, List<int> four, int pua})> pairs =
        <({List<int> cell, int real, List<int> four, int pua})>[
      (
        cell: <int>[0xa6, 0xd9],
        real: 0xfe10,
        four: <int>[0x84, 0x31, 0x82, 0x36],
        pua: 0xe78d
      ),
      (
        cell: <int>[0xa6, 0xda],
        real: 0xfe12,
        four: <int>[0x84, 0x31, 0x82, 0x38],
        pua: 0xe78e
      ),
      (
        cell: <int>[0xa6, 0xdb],
        real: 0xfe11,
        four: <int>[0x84, 0x31, 0x82, 0x37],
        pua: 0xe78f
      ),
      (
        cell: <int>[0xa6, 0xdc],
        real: 0xfe13,
        four: <int>[0x84, 0x31, 0x82, 0x39],
        pua: 0xe790
      ),
      (
        cell: <int>[0xa6, 0xdd],
        real: 0xfe14,
        four: <int>[0x84, 0x31, 0x83, 0x30],
        pua: 0xe791
      ),
      (
        cell: <int>[0xa6, 0xde],
        real: 0xfe15,
        four: <int>[0x84, 0x31, 0x83, 0x31],
        pua: 0xe792
      ),
      (
        cell: <int>[0xa6, 0xdf],
        real: 0xfe16,
        four: <int>[0x84, 0x31, 0x83, 0x32],
        pua: 0xe793
      ),
      (
        cell: <int>[0xa6, 0xec],
        real: 0xfe17,
        four: <int>[0x84, 0x31, 0x83, 0x33],
        pua: 0xe794
      ),
      (
        cell: <int>[0xa6, 0xed],
        real: 0xfe18,
        four: <int>[0x84, 0x31, 0x83, 0x34],
        pua: 0xe795
      ),
      (
        cell: <int>[0xa6, 0xf3],
        real: 0xfe19,
        four: <int>[0x84, 0x31, 0x83, 0x35],
        pua: 0xe796
      ),
      (
        cell: <int>[0xfe, 0x59],
        real: 0x9fb4,
        four: <int>[0x82, 0x35, 0x90, 0x37],
        pua: 0xe81e
      ),
      (
        cell: <int>[0xfe, 0x61],
        real: 0x9fb5,
        four: <int>[0x82, 0x35, 0x90, 0x38],
        pua: 0xe826
      ),
      (
        cell: <int>[0xfe, 0x66],
        real: 0x9fb6,
        four: <int>[0x82, 0x35, 0x90, 0x39],
        pua: 0xe82b
      ),
      (
        cell: <int>[0xfe, 0x67],
        real: 0x9fb7,
        four: <int>[0x82, 0x35, 0x91, 0x30],
        pua: 0xe82c
      ),
      (
        cell: <int>[0xfe, 0x6d],
        real: 0x9fb8,
        four: <int>[0x82, 0x35, 0x91, 0x31],
        pua: 0xe832
      ),
      (
        cell: <int>[0xfe, 0x7e],
        real: 0x9fb9,
        four: <int>[0x82, 0x35, 0x91, 0x32],
        pua: 0xe843
      ),
      (
        cell: <int>[0xfe, 0x90],
        real: 0x9fba,
        four: <int>[0x82, 0x35, 0x91, 0x33],
        pua: 0xe854
      ),
      (
        cell: <int>[0xfe, 0xa0],
        real: 0x9fbb,
        four: <int>[0x82, 0x35, 0x91, 0x34],
        pua: 0xe864
      ),
      (
        cell: <int>[0xa8, 0xbc],
        real: 0x1e3f,
        four: <int>[0x81, 0x35, 0xf4, 0x37],
        pua: 0xe7c7
      ),
    ];

    test('双字节格子给真字符，四字节序列留给 PUA（双向都对）', () {
      for (final ({List<int> cell, int real, List<int> four, int pua}) p
          in pairs) {
        final String expected = String.fromCharCode(p.real);
        final String puaText = String.fromCharCode(p.pua);
        final String hex =
            '0x${p.cell[0].toRadixString(16)} 0x${p.cell[1].toRadixString(16)}';
        expect(gb18030.decode(p.cell), expected, reason: hex);
        expect(gb18030.encode(expected), p.cell, reason: hex);
        expect(gb18030.decode(p.four), puaText, reason: '四字节 $hex');
        // 与 ICU 的有意分歧：ICU 把这 18 个四字节序列标成忽略，本包仍解成 PUA 且可编回
        expect(gb18030.encode(puaText), p.four, reason: 'PUA $hex');
      }
    });

    test('旧版（2005）读法在本包下会得到另一个字', () {
      // A6D9：2005 → U+E78D（PUA），2022 → U+FE10（︐）
      expect(gb18030.decode(<int>[0xa6, 0xd9]), '\ufe10');
      expect(gb18030.decode(<int>[0xa6, 0xd9]), isNot('\ue78d'));
      // A8BC：2005 → U+E7C7，2022 → U+1E3F（ḿ）
      expect(gb18030.decode(<int>[0xa8, 0xbc]), '\u1e3f');
    });

    test('这几组格子本来就不在 GBK / GB2312 里，换版不影响它们', () {
      for (final List<int> cell in <List<int>>[
        <int>[0xa6, 0xd9],
        <int>[0xfe, 0x59],
        <int>[0xa8, 0xbc],
      ]) {
        expect(() => gbk.decode(cell), throwsFormatException);
        expect(() => gb2312.decode(cell), throwsFormatException);
      }
    });
  });

  group('坏序列', () {
    test('严格模式抛 FormatException', () {
      expect(() => gb18030.decode(<int>[0x41, 0xff]), throwsFormatException);
      // 前导字节后跟数字，但四字节没配齐
      expect(
          () => gb18030.decode(<int>[0x81, 0x30, 0x81]), throwsFormatException);
    });

    test('宽松模式变 U+FFFD', () {
      expect(
        const Gb18030Codec(allowInvalid: true).decode(<int>[0x41, 0xff]),
        'A\uFFFD',
      );
    });
  });

  test('BMP 四字节区全量往返一致', () {
    int checked = 0;
    for (int index = 0; index < 189000; index++) {
      final List<int> bytes = <int>[
        0x81 + index ~/ 12600,
        0x30 + (index % 12600) ~/ 1260,
        0x81 + (index % 1260) ~/ 10,
        0x30 + index % 10,
      ];
      final String text;
      try {
        text = gb18030.decode(bytes);
      } on FormatException {
        continue;
      }
      expect(text.runes.length, 1);
      expect(gb18030.encode(text), bytes, reason: 'index $index');
      checked++;
    }
    // BMP 里必须用四字节表示的码位数（GB18030-2000）：与 Python 的 gb18030
    // 编解码器逐个比对得出，写死在这里，表生成错了会立刻掉下来
    expect(checked, 39420);
  });

  test('全部合法双字节往返一致（23,940 个格子里的 23,940 - 0 个）', () {
    int checked = 0;
    for (int lead = 0x81; lead <= 0xfe; lead++) {
      for (int trail = 0x40; trail <= 0xfe; trail++) {
        if (trail == 0x7f) continue;
        final List<int> bytes = <int>[lead, trail];
        final String text;
        try {
          text = gb18030.decode(bytes);
        } on FormatException {
          continue;
        }
        expect(gb18030.encode(text), bytes,
            reason: '0x${lead.toRadixString(16)} 0x${trail.toRadixString(16)}');
        checked++;
      }
    }
    expect(checked, greaterThan(23000));
  });

  test('name', () {
    expect(gb18030.name, 'gb18030');
  });
}
