import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

void main() {
  test('常见汉字与标点', () {
    expect(gb2312.decode(<int>[0xd6, 0xd0, 0xce, 0xc4]), '中文');
    expect(
      gb2312.decode(<int>[0xa3, 0xac, 0xa1, 0xa3, 0xa1, 0xa2]),
      '，。、',
    );
    expect(gb2312.encode('中文测试'),
        <int>[0xd6, 0xd0, 0xce, 0xc4, 0xb2, 0xe2, 0xca, 0xd4]);
  });

  test('日文假名在 GB2312 里也有（A4 区）', () {
    expect(gb2312.decode(<int>[0xa4, 0xa2, 0xa4, 0xa4, 0xa4, 0xa6]), 'あいう');
    expect(gb2312.encode('あいう'), <int>[0xa4, 0xa2, 0xa4, 0xa4, 0xa4, 0xa6]);
  });

  test('扩展汉字：GBK 有、GB2312 没有', () {
    // 镕：GBK 0xE946，GB2312 字符集里没有这个字
    expect(gbk.decode(<int>[0xe9, 0x46]), '镕');
    expect(() => gb2312.decode(<int>[0xe9, 0x46]), throwsFormatException);
    expect(() => gb2312.encode('镕'), throwsFormatException);
  });

  group('两个与 GBK 不一致的格子（历史遗留）', () {
    test('0xA1A4 在 GB2312 是「・」(U+30FB)，在 GBK 是「·」(U+00B7)', () {
      expect(gb2312.decode(<int>[0xa1, 0xa4]), '\u30fb');
      expect(gbk.decode(<int>[0xa1, 0xa4]), '\u00b7');
      expect(gb2312.encode('\u30fb'), <int>[0xa1, 0xa4]);
      // 反向不成立：GB2312 里没有 U+00B7 的位置
      expect(() => gb2312.encode('\u00b7'), throwsFormatException);
    });

    test('0xA1AA 在 GB2312 是「―」(U+2015)，在 GBK 是「—」(U+2014)', () {
      expect(gb2312.decode(<int>[0xa1, 0xaa]), '\u2015');
      expect(gbk.decode(<int>[0xa1, 0xaa]), '\u2014');
      expect(gb2312.encode('\u2015'), <int>[0xa1, 0xaa]);
      expect(() => gb2312.encode('\u2014'), throwsFormatException);
    });
  });

  test('严格 / 宽松', () {
    expect(() => gb2312.decode(<int>[0x41, 0xff]), throwsFormatException);
    expect(const Gb2312Codec(allowInvalid: true).decode(<int>[0x41, 0xff]),
        'A\uFFFD');
  });

  test('全部合法格子往返一致（7,445 个）', () {
    int checked = 0;
    for (int lead = 0x81; lead <= 0xfe; lead++) {
      for (int trail = 0x40; trail <= 0xfe; trail++) {
        if (trail == 0x7f) continue;
        final List<int> bytes = <int>[lead, trail];
        final String text;
        try {
          text = gb2312.decode(bytes);
        } on FormatException {
          continue;
        }
        expect(gb2312.encode(text), bytes,
            reason: '0x${lead.toRadixString(16)} 0x${trail.toRadixString(16)}');
        checked++;
      }
    }
    expect(checked, 7445);
  });

  test('name', () {
    expect(gb2312.name, 'gb2312');
  });
}
