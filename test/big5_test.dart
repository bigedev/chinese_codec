import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

/// 期望值来自 CPython 的 `cp950` 编解码器。
void main() {
  group('解码', () {
    test('常见繁体', () {
      expect(big5.decode(<int>[0xa4, 0xa4, 0xa4, 0xe5]), '中文');
      expect(
        big5.decode(<int>[0xc1, 0x63, 0xc5, 0xe9, 0xa4, 0xa4, 0xa4, 0xe5]),
        '繁體中文',
      );
      expect(big5.decode(<int>[0xbb, 0x4f, 0xc6, 0x57]), '臺灣');
    });

    test('中文标点', () {
      expect(big5.decode(<int>[0xa1, 0x43]), '。');
      expect(big5.decode(<int>[0xa1, 0x41]), '，');
      expect(big5.decode(<int>[0xa1, 0x49]), '！');
    });

    test('CP950 独有的格子（经典 Big5 里没有）', () {
      expect(big5.decode(<int>[0xa3, 0xe1]), '€');
      expect(big5.encode('€'), <int>[0xa3, 0xe1]);
    });

    test('ASCII 与空输入', () {
      expect(big5.decode(<int>[0x41, 0x42]), 'AB');
      expect(big5.decode(const <int>[]), '');
    });

    test('严格模式：坏字节与越界首尾字节', () {
      expect(() => big5.decode(<int>[0x41, 0xff]), throwsFormatException);
      // 首字节 0xA0 不在 0xA1-0xF9
      expect(() => big5.decode(<int>[0xa0, 0x40]), throwsFormatException);
      // 首字节 0xFA 之后留给用户自定义区，CP950 不认
      expect(() => big5.decode(<int>[0xfa, 0x40]), throwsFormatException);
      // 第二字节 0x7F / 0x80 / 0xA0 都是空的
      for (final int trail in <int>[0x7f, 0x80, 0xa0]) {
        expect(() => big5.decode(<int>[0xa4, trail]), throwsFormatException,
            reason: 'trail 0x${trail.toRadixString(16)}');
      }
    });

    test('宽松模式：坏字节变 U+FFFD', () {
      expect(
        const Big5Codec(allowInvalid: true).decode(<int>[0x41, 0xff]),
        'A\uFFFD',
      );
    });
  });

  group('编码', () {
    test('常见繁体', () {
      expect(big5.encode('中文'), <int>[0xa4, 0xa4, 0xa4, 0xe5]);
      expect(big5.encode('臺灣'), <int>[0xbb, 0x4f, 0xc6, 0x57]);
    });

    test('简体字在 Big5 里编不出来', () {
      for (final String ch in <String>['汉', '简', '国']) {
        expect(() => big5.encode(ch), throwsFormatException, reason: ch);
      }
    });

    test('CP950 不含 HKSCS 扩展（要用 big5hkscs）', () {
      // HKSCS：U+23CB7 → 0x9DB7（首字节 0x9D 在 CP950 范围外）
      expect(() => big5.encode('\u{23CB7}'), throwsFormatException);
      expect(() => big5.decode(<int>[0x9d, 0xb7]), throwsFormatException);
      expect(big5hkscs.decode(<int>[0x9d, 0xb7]), '\u{23CB7}');
    });
  });

  test('全部合法格子往返一致（13,752 个，允许重复码位换格子）', () {
    int checked = 0;
    for (int lead = 0xa1; lead <= 0xf9; lead++) {
      for (int trail = 0x40; trail <= 0xfe; trail++) {
        if (trail > 0x7e && trail < 0xa1) continue;
        final List<int> bytes = <int>[lead, trail];
        final String text;
        try {
          text = big5.decode(bytes);
        } on FormatException {
          continue;
        }
        expect(text.runes.length, 1);
        // CP950 有 10 个码位被两个格子映射，所以比的是「解回来的字」而非原字节
        expect(big5.decode(big5.encode(text)), text,
            reason: '0x${lead.toRadixString(16)} 0x${trail.toRadixString(16)}');
        checked++;
      }
    }
    expect(checked, 13752);
  });

  test('name', () {
    expect(big5.name, 'big5');
    expect(big5.toString(), 'big5');
  });
}
