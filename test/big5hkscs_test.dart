import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

/// 期望值来自 WHATWG Encoding Standard 的 `index-big5.txt`（Big5 + HKSCS-2008）
/// 与规范正文的「Pointer / Code points」表，本包的生成脚本逐格对照过。
void main() {
  group('解码', () {
    test('常见繁体（与 CP950 相同的部分）', () {
      expect(big5hkscs.decode(<int>[0xa4, 0xa4, 0xa4, 0xe5]), '中文');
      expect(
        big5hkscs.decode(<int>[0xc1, 0x63, 0xc5, 0xe9, 0xa4, 0xa4, 0xa4, 0xe5]),
        '繁體中文',
      );
      expect(big5hkscs.decode(<int>[0xbb, 0x4f, 0xc6, 0x57]), '臺灣');
    });

    test('HKSCS 扩展区：0x87-0xA0 与 0xF9-0xFE 是 CP950 没有的', () {
      // 0x9DB7 首字节 0x9D 在 CP950 的 0xA1-0xF9 之外
      expect(() => big5.decode(<int>[0x9d, 0xb7]), throwsFormatException);
      expect(big5hkscs.decode(<int>[0x9d, 0xb7]), '\u{23CB7}');
      // 0xFE 也是 CP950 保留给用户自定义区的
      expect(() => big5.decode(<int>[0xfe, 0xfe]), throwsFormatException);
      expect(big5hkscs.decode(<int>[0xfe, 0xfe]), '秔');
      expect(big5hkscs.decode(<int>[0x87, 0x7b]), '\u{21D53}');
    });

    test('补充平面码位（1,713 个）不只是 BMP', () {
      const List<int> bytes = <int>[0x9d, 0xb7];
      final String text = big5hkscs.decode(bytes);
      expect(text.runes.single, 0x23cb7);
      expect(text.length, 2, reason: 'UTF-16 里是代理对');
    });

    test('与 CP950 冲突的格子按 HKSCS 解释', () {
      // HKSCS 把 ETen 扩展的假名区（0xC6A1-0xC8FE）拿去放带圈数字与汉字
      expect(big5.decode(<int>[0xc6, 0xa1]), 'ヾ');
      expect(big5hkscs.decode(<int>[0xc6, 0xa1]), '①');
      // 「€」两边一致（WHATWG 与 CP950 都认这格）
      expect(big5hkscs.decode(<int>[0xa3, 0xe1]), '€');
    });

    test('一格对两个码位的组合字符', () {
      expect(big5hkscs.decode(<int>[0x88, 0x62]), '\u00ca\u0304');
      expect(big5hkscs.decode(<int>[0x88, 0x64]), '\u00ca\u030c');
      expect(big5hkscs.decode(<int>[0x88, 0xa3]), '\u00ea\u0304');
      expect(big5hkscs.decode(<int>[0x88, 0xa5]), '\u00ea\u030c');
      expect(big5hkscs.decode(<int>[0x88, 0x62]).length, 2);
    });

    test('ASCII 与空输入', () {
      expect(big5hkscs.decode(<int>[0x41, 0x42]), 'AB');
      expect(big5hkscs.decode(const <int>[]), '');
    });

    test('严格模式：坏字节与越界首尾字节', () {
      expect(() => big5hkscs.decode(<int>[0x41, 0xff]), throwsFormatException);
      // 0x81-0x86 是规范预留、未分配的首字节
      expect(
        () => big5hkscs.decode(<int>[0x81, 0x40]),
        throwsFormatException,
      );
      // 第二字节 0x7F / 0x80 / 0xA0 都是空的
      for (final int trail in <int>[0x7f, 0x80, 0xa0]) {
        expect(
          () => big5hkscs.decode(<int>[0xa4, trail]),
          throwsFormatException,
          reason: 'trail 0x${trail.toRadixString(16)}',
        );
      }
    });

    test('宽松模式：坏字节变 U+FFFD', () {
      expect(
        const Big5HkscsCodec(allowInvalid: true).decode(<int>[0x41, 0xff]),
        'A\uFFFD',
      );
    });
  });

  group('编码', () {
    test('常见繁体', () {
      expect(big5hkscs.encode('中文'), <int>[0xa4, 0xa4, 0xa4, 0xe5]);
      expect(big5hkscs.encode('臺灣'), <int>[0xbb, 0x4f, 0xc6, 0x57]);
    });

    test('扩展区与补充平面', () {
      expect(big5hkscs.encode('\u{23CB7}'), <int>[0x9d, 0xb7]);
      expect(big5hkscs.encode('秔'), <int>[0xfe, 0xfe]);
      expect(big5hkscs.encode('\u{21D53}'), <int>[0x87, 0x7b]);
    });

    test('组合字符整体编回一格，单独的 Ê 是另一格', () {
      expect(big5hkscs.encode('\u00ca'), <int>[0x88, 0x66]);
      expect(big5hkscs.encode('\u00ca\u0304'), <int>[0x88, 0x62]);
      expect(big5hkscs.encode('\u00ea\u030c'), <int>[0x88, 0xa5]);
    });

    test('组合字符混在文本里也能往返', () {
      const List<int> bytes = <int>[0xa4, 0xa4, 0x88, 0x62, 0xa4, 0xe5];
      expect(big5hkscs.decode(bytes), '中\u00ca\u0304文');
      expect(big5hkscs.encode('中\u00ca\u0304文'), bytes);
    });

    test('编不出来的字符抛 FormatException', () {
      // HKSCS 顺手收了一部分简体字（「汉」在 0xFAE4、「国」在 0x98C7），
      // 但远不是全部 —— 「简」就不在表里
      expect(big5hkscs.encode('汉'), <int>[0xfa, 0xe4]);
      expect(big5hkscs.encode('国'), <int>[0x98, 0xc7]);
      for (final String ch in <String>['简', '\u{1F600}']) {
        expect(() => big5hkscs.encode(ch), throwsFormatException, reason: ch);
      }
    });
  });

  test('全部合法格子往返一致（18,594 个，允许重复码位换格子）', () {
    int checked = 0;
    for (int lead = 0x87; lead <= 0xfe; lead++) {
      for (int trail = 0x40; trail <= 0xfe; trail++) {
        if (trail > 0x7e && trail < 0xa1) continue;
        final List<int> bytes = <int>[lead, trail];
        final String text;
        try {
          text = big5hkscs.decode(bytes);
        } on FormatException {
          continue;
        }
        // 有 100 个码位占两个格子，所以比「解回来的字」而不是原字节
        expect(
          big5hkscs.decode(big5hkscs.encode(text)),
          text,
          reason: '0x${lead.toRadixString(16)} 0x${trail.toRadixString(16)}',
        );
        checked++;
      }
    }
    expect(checked, 18594);
  });

  test('CP950 的每个格子 HKSCS 都能解（格子是超集）', () {
    int checked = 0;
    for (int lead = 0xa1; lead <= 0xf9; lead++) {
      for (int trail = 0x40; trail <= 0xfe; trail++) {
        if (trail > 0x7e && trail < 0xa1) continue;
        final List<int> bytes = <int>[lead, trail];
        try {
          big5.decode(bytes);
        } on FormatException {
          continue;
        }
        expect(
          () => big5hkscs.decode(bytes),
          returnsNormally,
          reason: '0x${lead.toRadixString(16)} 0x${trail.toRadixString(16)}',
        );
        checked++;
      }
    }
    expect(checked, 13752);
  });

  test('name', () {
    expect(big5hkscs.name, 'big5-hkscs');
    expect(big5hkscs.toString(), 'big5-hkscs');
  });
}
