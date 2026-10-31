import 'dart:convert';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

void main() {
  test('chineseCodecs 先简体（由宽到窄）后繁体', () {
    expect(
      chineseCodecs.map((Encoding codec) => codec.name),
      <String>['gb18030', 'gbk', 'gb2312', 'big5', 'big5-hkscs'],
    );
  });

  test('按名字取编码，认常见别名', () {
    expect(chineseEncodingByName('GBK'), same(gbk));
    expect(chineseEncodingByName('cp936'), same(gbk));
    expect(chineseEncodingByName('ms936'), same(gbk));
    expect(chineseEncodingByName('GB18030'), same(gb18030));
    expect(chineseEncodingByName('GB_2312'), same(gb2312));
    expect(chineseEncodingByName('euc-cn'), same(gb2312));
    expect(chineseEncodingByName('BIG5'), same(big5));
    expect(chineseEncodingByName('cp950'), same(big5));
    expect(chineseEncodingByName('big-5'), same(big5));
    expect(chineseEncodingByName('big5-hkscs'), same(big5hkscs));
    expect(chineseEncodingByName('Big5-HKSCS'), same(big5hkscs));
    expect(chineseEncodingByName('big5hkscs'), same(big5hkscs));
    expect(chineseEncodingByName('hkscs'), same(big5hkscs));
    expect(chineseEncodingByName('shift_jis'), isNull);
    expect(chineseEncodingByName('gb18030-2022'), isNull);
    expect(chineseEncodingByName(''), isNull);
  });

  test('三者都是 Encoding，可直接用于 Codec 接口', () {
    for (final Encoding codec in chineseCodecs) {
      expect(codec, isA<Encoding>());
      expect(codec.decoder.convert(ascii.encode('ok')), 'ok');
      expect(codec.encoder.convert('ok'), ascii.encode('ok'));
    }
  });

  test('一行混排（ASCII + 汉字）', () {
    const String line = 'Print "中文" 2026';
    final List<int> gbkBytes = <int>[
      0x50, 0x72, 0x69, 0x6e, 0x74, 0x20, 0x22, //
      0xd6, 0xd0, 0xce, 0xc4, 0x22, 0x20, 0x32, 0x30, 0x32, 0x36,
    ];
    expect(gbk.decode(gbkBytes), line);
    expect(gbk.encode(line), gbkBytes);
    expect(gb18030.decode(gbkBytes), line);
    expect(gb2312.decode(gbkBytes), line);
  });
}
