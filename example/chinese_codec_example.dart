import 'package:chinese_codec/chinese_codec.dart';

void main() {
  // 「中文」在 GBK / GB18030 / GB2312 下都是这两个双字节
  const List<int> simplified = <int>[0xd6, 0xd0, 0xce, 0xc4];
  print(gbk.decode(simplified)); // 中文
  print(gbk.encode('中文')); // [214, 208, 206, 196]

  // 同一个词在 Big5（CP950）下是另一套字节
  print(big5.decode(<int>[0xa4, 0xa4, 0xa4, 0xe5])); // 中文
  print(big5.encode('繁體中文'));

  // 香港增补字符集：CP950 读不了扩展区，Big5-HKSCS 能
  print(big5hkscs.decode(<int>[0x9d, 0xb7])); // 𣲷
  print(big5hkscs.encode('\u{23CB7}')); // [157, 183]

  // 四字节：U+10000（补充平面）只有 GB18030 编得出来
  const String rare = '\u{10000}';
  final List<int> encoded = gb18030.encode(rare);
  print(encoded.map((int b) => b.toRadixString(16)).join(' ')); // 90 30 81 30
  print(gb18030.decode(encoded) == rare); // true

  // 按名字取，认别名
  print(chineseEncodingByName('cp936')); // GbkCodec
  print(chineseEncodingByName('cp950')); // Big5Codec
  print(chineseEncodingByName('big5-hkscs')); // Big5HkscsCodec
}
