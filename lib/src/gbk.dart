import 'double_byte_codec.dart';
import 'gb_layout.dart';

/// GBK（CP936）编解码。
///
/// 双字节，单字节部分只接受 ASCII。汉字区与 GB18030 的双字节区一致，
/// 只是 GBK 不接受其中 2,149 个用户自定义区格子（那些只在 GB18030 里合法）。
class GbkCodec extends DoubleByteCodec {
  /// 创建一个 GBK 编解码实例。
  ///
  /// [allowInvalid] 决定解码时坏字节怎么处理，详见同名字段。
  const GbkCodec({super.allowInvalid});

  /// 编码名，固定为 `'gbk'`。
  ///
  /// 与 `toString()` 的返回值一致，也是下面 [gbk] 实例在 `chineseCodecs` 里的名字。
  @override
  String get name => 'gbk';

  /// GBK 的字节映射表。
  ///
  /// 与 GB18030 的双字节区同一张表，只额外加了「哪些格子收」的位图：
  /// 2,149 个用户自定义区格子在这里不合法。
  @override
  DoubleByteLayout get layout => gbkLayout;
}

/// GBK 的共享实例（严格模式，坏字节抛 [FormatException]）。
const GbkCodec gbk = GbkCodec();
