/// 中文字符集编解码：GB18030 / GBK / GB2312 / Big5 / Big5-HKSCS，纯 Dart，
/// 无原生依赖。
///
/// `dart:convert` 只有 UTF-8 / Latin-1 / ASCII，遇到老文件（VB、Delphi、Windows 上
/// 存盘的文本）只能报「不是 UTF-8」。这个包补上五种中文编码：
///
/// ```dart
/// import 'package:chinese_codec/chinese_codec.dart';
///
/// final String text = gbk.decode(bytes);       // 严格：坏字节抛 FormatException
/// final List<int> back = gb18030.encode(text); // 编不出来的字符抛 FormatException
/// final String trad = big5.decode(twBytes);    // 繁体（CP950，Windows 常见）
/// final String hk = big5hkscs.decode(hkBytes); // 繁体（香港增补字符集）
/// ```
///
/// 想「尽量读出来」时用带 `allowInvalid` 的实例（坏字节变成 U+FFFD，
/// 与 `utf8.decode(allowMalformed: true)` 同义）：
///
/// ```dart
/// const GbkCodec lenient = GbkCodec(allowInvalid: true);
/// final String text = lenient.decode(bytes);
/// ```
library;

import 'dart:convert';

import 'src/big5.dart';
import 'src/big5hkscs.dart';
import 'src/gb18030.dart';
import 'src/gb2312.dart';
import 'src/gbk.dart';

export 'src/big5.dart' show Big5Codec, big5;
export 'src/big5hkscs.dart' show Big5HkscsCodec, big5hkscs;
export 'src/gb18030.dart' show Gb18030Codec, gb18030;
export 'src/gb2312.dart' show Gb2312Codec, gb2312;
export 'src/gbk.dart' show GbkCodec, gbk;

/// 本包提供的五种编码：GB18030 / GBK / GB2312 是简体（由宽到窄），
/// Big5 / Big5-HKSCS 是繁体（后者是香港增补字符集，格子更多但与 CP950 有冲突）。
const List<Encoding> chineseCodecs = <Encoding>[
  gb18030,
  gbk,
  gb2312,
  big5,
  big5hkscs,
];

/// 按名字取编码，认常见别名；不认识返回 null。
///
/// ```dart
/// chineseEncodingByName('CP936');      // → gbk
/// chineseEncodingByName('GB_2312');   // → gb2312
/// chineseEncodingByName('CP950');     // → big5
/// chineseEncodingByName('big5-hkscs');// → big5hkscs
/// ```
Encoding? chineseEncodingByName(String name) => switch (name.toLowerCase()) {
      'gbk' || 'cp936' || 'ms936' || 'windows-936' => gbk,
      'gb18030' => gb18030,
      'gb2312' || 'gb_2312' || 'gb_2312-80' || 'euc-cn' || 'csgb2312' => gb2312,
      'big5-hkscs' || 'big5hkscs' || 'big5_hkscs' || 'hkscs' => big5hkscs,
      'big5' || 'big-5' || 'cp950' || 'ms950' || 'windows-950' => big5,
      _ => null,
    };
