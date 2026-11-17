import 'dart:convert';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

/// 简体「中文」的 GBK 字节。
const List<int> kSimplified = <int>[0xd6, 0xd0, 0xce, 0xc4];

/// 繁体「中文」的 Big5 字节。
const List<int> kTraditional = <int>[0xa4, 0xa4, 0xa4, 0xe5];

void main() {
  group('tryDecode', () {
    test('能解时返回文本', () {
      expect(tryDecode(kSimplified, gbk), '中文');
      expect(tryDecode(kTraditional, big5), '中文');
    });

    test('解不出来返回 null 而不是抛异常', () {
      // 0x9D 是 HKSCS 扩展区的首字节，GB2312 没有这个区
      expect(tryDecode(<int>[0x9d, 0xb7], gb2312), isNull);
      // GBK 字节不是合法 UTF-8
      expect(tryDecode(kSimplified, utf8), isNull);
    });

    test('语义跟随传入的实例：严格实例给 null，宽松实例照旧替换', () {
      const GbkCodec lenient = GbkCodec(allowInvalid: true);
      expect(tryDecode(<int>[0xff], gbk), isNull);
      expect(tryDecode(<int>[0xff], lenient), '\uFFFD');
    });
  });

  group('verifyRoundTrip', () {
    test('合法且规范写法的字节通过', () {
      expect(verifyRoundTrip(kSimplified, gbk), isTrue);
      expect(verifyRoundTrip(kTraditional, big5), isTrue);
    });

    test('GB18030 四字节：只有 gb18030 通过', () {
      final List<int> fourByte = gb18030.encode('\u{10000}');
      expect(fourByte.length, 4);
      expect(verifyRoundTrip(fourByte, gb18030), isTrue);
      expect(verifyRoundTrip(fourByte, gbk), isFalse);
      expect(verifyRoundTrip(fourByte, big5), isFalse);
    });

    test('Big5 的非规范重复格不通过（文本仍然对）', () {
      // 十：规范格 0xA451，老表里还有一个 0xA2CC
      expect(big5.decode(<int>[0xa4, 0x51]), '十');
      expect(big5.decode(<int>[0xa2, 0xcc]), '十');
      expect(verifyRoundTrip(<int>[0xa4, 0x51], big5), isTrue);
      expect(verifyRoundTrip(<int>[0xa2, 0xcc], big5), isFalse);
    });

    test('简体字节按 Big5 也能通过回环 —— 回环不判断语义', () {
      // 这条是「不能拿回环当简繁判定」的证据：同一个字节序列五家全过。
      expect(verifyRoundTrip(kSimplified, big5), isTrue);
      expect(big5.decode(kSimplified), '笢恅');
      expect(codecsThatRoundTrip(kSimplified).length, 5);
    });
  });

  group('codecsThatRoundTrip', () {
    test('空输入不构成证据', () {
      expect(codecsThatRoundTrip(const <int>[]), isEmpty);
    });

    test('GB18030 四字节只剩 gb18030', () {
      final List<Encoding> fits = codecsThatRoundTrip(
        gb18030.encode('\u{10000}'),
      );
      expect(fits.map((Encoding e) => e.name), <String>['gb18030']);
    });

    test('排除 GB2312 装不下的字', () {
      final List<Encoding> fits = codecsThatRoundTrip(<int>[0x9d, 0xb7]);
      expect(
        fits.map((Encoding e) => e.name),
        <String>['gb18030', 'gbk', 'big5-hkscs'],
      );
    });

    test('二进制一条都不剩', () {
      expect(
        codecsThatRoundTrip(<int>[0x00, 0x01, 0x02, 0x03, 0xfe, 0xff]),
        isEmpty,
      );
    });

    test('candidates 限定生效', () {
      final List<Encoding> fits = codecsThatRoundTrip(
        kSimplified,
        candidates: <Encoding>[gbk],
      );
      expect(fits, <Encoding>[gbk]);
    });
  });

  group('decodeLossy', () {
    test('干净输入与严格解码一致', () {
      final DecodeReport report = GbkCodec().decodeLossy(kSimplified);
      expect(report.isClean, isTrue);
      expect(report.lostBytes, 0);
      expect(report.text, gbk.decode(kSimplified));
    });

    test('坏字节逐个记偏移', () {
      // 0x61 直通、0xFF 非法、0x62 直通、0xA4 是首字节但没有次字节
      final DecodeReport report = GbkCodec().decodeLossy(<int>[
        0x61,
        0xff,
        0x62,
        0xa4,
      ]);
      expect(report.lostOffsets, <int>[1, 3]);
      expect(report.lostBytes, 2);
      expect(report.text, 'a\uFFFDb\uFFFD');
    });

    test('GB18030 凑不齐的四字节序列按字节记', () {
      // 0x81 0x30 开头 ⇒ 必须四字节；第三字节 0x81 合法、第四字节 0x20 不是数字
      final DecodeReport report = gb18030.decodeLossy(<int>[
        0x81,
        0x30,
        0x81,
        0x20,
      ]);
      expect(report.lostOffsets, <int>[0, 2]);
      // 夹在中间的 '0' 与尾部的空格都没被吞掉
      expect(report.text, '\uFFFD0\uFFFD ');
    });

    test('不受 allowInvalid 影响', () {
      const GbkCodec lenient = GbkCodec(allowInvalid: true);
      expect(lenient.decodeLossy(<int>[0xff]).lostOffsets, <int>[0]);
      expect(gbk.decodeLossy(<int>[0xff]).lostOffsets, <int>[0]);
    });
  });

  group('unrepresentableRunes', () {
    test('全部能表示时为空', () {
      expect(unrepresentableRunes('中文abc', gbk), isEmpty);
    });

    test('超出字符集的码位被列出', () {
      expect(unrepresentableRunes('中文\u{10000}', gbk), <int>[0x10000]);
      // GB2312 比 GBK 窄：HKSCS 扩展区的字它也装不下
      expect(
        unrepresentableRunes('𣲷', gb18030),
        isEmpty,
      );
      expect(unrepresentableRunes('𣲷', gb2312), <int>[0x23CB7]);
    });

    test('重复出现重复列出（不去重）', () {
      expect(unrepresentableRunes('a\u{10000}b\u{10000}', gbk), <int>[
        0x10000,
        0x10000,
      ]);
    });
  });
}
