import 'double_byte_codec.dart';
import 'gb_layout.dart';

/// GB2312（EUC-CN）编解码。
///
/// 真子集（7,445 个双字节字符）：只收 GB2312 字符集的格子，GBK 里多出来的
/// 扩展汉字在这里解不出来、也编不出去。
///
/// 有两个格子与 GBK / GB18030 映射到不同码位（历史遗留）：
/// `0xA1A4` 是「・」(U+30FB)、`0xA1AA` 是「―」(U+2015)。GB2312 编码按自己那套，
/// 因此 U+00B7 / U+2014 在 GB2312 里不可表示。
class Gb2312Codec extends DoubleByteCodec {
  const Gb2312Codec({super.allowInvalid});

  @override
  String get name => 'gb2312';

  @override
  DoubleByteLayout get layout => gb2312Layout;
}

/// GB2312 的共享实例。
const Gb2312Codec gb2312 = Gb2312Codec();
