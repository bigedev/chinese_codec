/// 五种编码的登记表：共享实例与按名字查找。
///
/// 从 `chinese_codec.dart` 拆出来，是为了让 `inspect.dart`（试解 / 回环校验）
/// 也能拿到这份列表 —— 否则两个文件互相 import，环就绕在库入口上。
library;

import 'dart:convert';

import 'big5.dart';
import 'big5hkscs.dart';
import 'gb18030.dart';
import 'gb2312.dart';
import 'gbk.dart';

/// 本包提供的五种编码：GB18030 / GBK / GB2312 是简体（由宽到窄），
/// Big5 / Big5-HKSCS 是繁体（后者是香港增补字符集，格子更多但与 CP950 有冲突）。
///
/// 顺序固定：简体三家在前（由宽到窄）、繁体两家在后；全部是严格模式的共享实例。
///
/// [codecsThatRoundTrip] 的默认候选就是这个列表，返回顺序也与之相同 —— 想取
/// 「能完整表示这段字节的最窄简体编码」时，取返回值里最后一个 GB 系编码即可。
const List<Encoding> chineseCodecs = <Encoding>[
  gb18030,
  gbk,
  gb2312,
  big5,
  big5hkscs,
];

/// 按名字取编码，认常见别名；不认识返回 null。
///
/// 大小写不敏感，首尾空白会被去掉（HTTP 头里 `charset=GBK ` 这种很常见）。
/// 返回的是本包的共享实例，所以可以直接比较身份
/// （`identical(chineseEncodingByName('CP936'), gbk)` 成立）。
///
/// `gb18030-2000` / `gb18030-2022` 都映射到 [gb18030]：本包实现的是 2022 版映射，
/// 而这两个名字只是标签（老文件标成 2000 的，按 2022 解也只在那 19 组上有差别）。
///
/// `dart:convert` 的 `Encoding.getByName` 只认 utf-8 / latin1 / ascii，
/// 中文编码走这个函数。
///
/// ```dart
/// chineseEncodingByName('CP936');      // → gbk
/// chineseEncodingByName('GB_2312');   // → gb2312
/// chineseEncodingByName('CP950');     // → big5
/// chineseEncodingByName('big5-hkscs');// → big5hkscs
/// chineseEncodingByName('shift_jis'); // → null（不认识的编码）
/// ```
Encoding? chineseEncodingByName(String name) =>
    switch (name.trim().toLowerCase()) {
      'gbk' ||
      'cp936' ||
      'cp-936' ||
      'ms936' ||
      'windows-936' ||
      'x-gbk' =>
        gbk,
      'gb18030' || 'gb18030-2000' || 'gb18030-2022' => gb18030,
      'gb2312' ||
      'gb-2312' ||
      'gb_2312' ||
      'gb_2312-80' ||
      'euc-cn' ||
      'csgb2312' =>
        gb2312,
      'big5-hkscs' || 'big5hkscs' || 'big5_hkscs' || 'hkscs' => big5hkscs,
      'big5' ||
      'big-5' ||
      'cp950' ||
      'cp-950' ||
      'ms950' ||
      'windows-950' =>
        big5,
      _ => null,
    };
