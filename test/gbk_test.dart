import 'dart:convert';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

/// 期望值来自 CPython 的 `gbk` 编解码器（同一套 CP936 映射），不是本包的自我循环。
void main() {
  group('解码', () {
    test('常见汉字', () {
      expect(gbk.decode(<int>[0xd6, 0xd0, 0xce, 0xc4]), '中文');
      expect(
        gbk.decode(<int>[
          0xd6, 0xd0, 0xbb, 0xaa, 0xc8, 0xcb, //
          0xc3, 0xf1, 0xb9, 0xb2, 0xba, 0xcd, 0xb9, 0xfa,
        ]),
        '中华人民共和国',
      );
    });

    test('中文标点', () {
      expect(
        gbk.decode(<int>[
          0xa3,
          0xac,
          0xa1,
          0xa3,
          0xa1,
          0xa2,
          0xa3,
          0xbb,
          0xa3,
          0xba,
          0xa3,
          0xbf,
          0xa3,
          0xa1,
        ]),
        '，。、；：？！',
      );
    });

    test('ASCII 原样通过', () {
      expect(gbk.decode(ascii.encode('ABC abc 123 !~')), 'ABC abc 123 !~');
    });

    test('空输入', () {
      expect(gbk.decode(const <int>[]), '');
    });

    test('严格模式：坏字节抛 FormatException 并给出偏移', () {
      expect(
        () => gbk.decode(<int>[0x41, 0xff, 0x41]),
        throwsA(
          isA<FormatException>()
              .having((FormatException e) => e.offset, 'offset', 1),
        ),
      );
    });

    test('严格模式：截断的双字节序列', () {
      expect(() => gbk.decode(<int>[0xd6]), throwsFormatException);
    });

    test('宽松模式：坏字节变 U+FFFD，其余照解', () {
      const GbkCodec lenient = GbkCodec(allowInvalid: true);
      expect(lenient.decode(<int>[0x41, 0xff, 0x41]), 'A\uFFFDA');
      expect(lenient.decode(<int>[0xd6, 0xd0, 0xff]), '中\uFFFD');
    });
  });

  group('编码', () {
    test('常见汉字', () {
      expect(gbk.encode('中文'), <int>[0xd6, 0xd0, 0xce, 0xc4]);
      expect(
        gbk.encode('中华人民共和国'),
        <int>[
          0xd6, 0xd0, 0xbb, 0xaa, 0xc8, 0xcb, //
          0xc3, 0xf1, 0xb9, 0xb2, 0xba, 0xcd, 0xb9, 0xfa,
        ],
      );
    });

    test('ASCII 与空串', () {
      expect(gbk.encode('abc'), <int>[0x61, 0x62, 0x63]);
      expect(gbk.encode(''), isEmpty);
    });

    test('GBK 之外的字符抛 FormatException', () {
      expect(() => gbk.encode('\u{1F600}'), throwsFormatException);
      // 补充平面一律编不出来（GBK 没有四字节形式）
      expect(() => gbk.encode('\u{10000}'), throwsFormatException);
    });
  });

  test('全部合法格子往返一致（21,791 个）', () {
    int checked = 0;
    for (int lead = 0x81; lead <= 0xfe; lead++) {
      for (int trail = 0x40; trail <= 0xfe; trail++) {
        if (trail == 0x7f) continue;
        final List<int> bytes = <int>[lead, trail];
        final String text;
        try {
          text = gbk.decode(bytes);
        } on FormatException {
          continue;
        }
        expect(text.runes.length, 1);
        expect(gbk.encode(text), bytes,
            reason: '0x${lead.toRadixString(16)} 0x${trail.toRadixString(16)}');
        checked++;
      }
    }
    expect(checked, 21791);
  });

  test('不接受 GB18030 才有的用户自定义区格子', () {
    // 与 gb18030_test 里同一组字节对照：GBK 不认，GB18030 认
    expect(() => gbk.decode(<int>[0xa1, 0x40]), throwsFormatException);
  });

  test('name 与 toString', () {
    expect(gbk.name, 'gbk');
    expect(gbk.toString(), 'gbk');
    expect(gbk, isA<Encoding>());
  });
}
