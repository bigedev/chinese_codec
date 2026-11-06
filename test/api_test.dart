import 'dart:async';
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
    expect(chineseEncodingByName(''), isNull);
    // 首尾空白要去掉：HTTP 头里 `charset=GBK ` 很常见
    expect(chineseEncodingByName(' gbk '), same(gbk));
    expect(chineseEncodingByName('\tBig5\n'), same(big5));
    // 常见写法变体
    expect(chineseEncodingByName('gb-2312'), same(gb2312));
    expect(chineseEncodingByName('x-gbk'), same(gbk));
    expect(chineseEncodingByName('cp-936'), same(gbk));
    expect(chineseEncodingByName('cp-950'), same(big5));
    // GB18030 的版本号标签都指向同一实现（本实现按 2022 版映射）
    expect(chineseEncodingByName('gb18030-2022'), same(gb18030));
    expect(chineseEncodingByName('gb18030-2000'), same(gb18030));
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

  test('decodeStream 跨 chunk 切断多字节字符也能解', () async {
    const String text = '中文';
    final List<int> gbkBytes = gbk.encode(text);
    // 故意按 1 / 2 / 剩余 切开，让汉字的两字节分属不同 chunk
    Stream<List<int>> split(List<int> bytes) => Stream<List<int>>.fromIterable(
          <List<int>>[
            bytes.sublist(0, 1),
            bytes.sublist(1, 3),
            bytes.sublist(3),
          ],
        );

    expect(await gbk.decodeStream(split(gbkBytes)), text);
    expect(await gb18030.decodeStream(split(gbkBytes)), text);
    expect(await gb2312.decodeStream(split(gbkBytes)), text);
    expect(await big5.decodeStream(Stream<List<int>>.empty()), '');
    expect(
      await const GbkCodec(allowInvalid: true)
          .decodeStream(Stream<List<int>>.fromIterable(<List<int>>[
        <int>[0x80],
      ])),
      '\uFFFD',
    );
  });

  group('ChunkedConversion（0.1.2 之前这里全抛 UnsupportedError）', () {
    test('decoder.bind 跨 chunk 收齐再解', () async {
      const String text = '中文混合ASCII';
      final List<int> bytes = gbk.encode(text);
      final String decoded = await gbk.decoder
          .bind(Stream<List<int>>.fromIterable(<List<int>>[
            bytes.sublist(0, 1),
            bytes.sublist(1, 3),
            bytes.sublist(3),
          ]))
          .join();
      expect(decoded, text);
    });

    test('encoder.bind 逐块编码并拼接', () async {
      const String text = '中文混合ASCII';
      final List<int> bytes = await gbk.encoder
          .bind(Stream<String>.fromIterable(<String>['中文', '混合ASCII']))
          .expand((List<int> chunk) => chunk)
          .toList();
      expect(bytes, gbk.encode(text));
    });

    test('stream.transform(codec.decoder) 能走通', () async {
      final List<int> bytes = gb18030.encode('中文');
      expect(
        await Stream<List<int>>.value(bytes).transform(gb18030.decoder).join(),
        '中文',
      );
    });

    test('GB18030 四字节序列被切成两半也能解', () async {
      const String rare = '\u{10000}';
      final List<int> four = gb18030.encode(rare);
      final String decoded = await gb18030.decoder
          .bind(Stream<List<int>>.fromIterable(<List<int>>[
            four.sublist(0, 2),
            four.sublist(2),
          ]))
          .join();
      expect(decoded, rare);
    });
  });
}
