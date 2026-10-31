import 'double_byte_codec.dart';
import 'gb_layout.dart';

/// GBK（CP936）编解码。
///
/// 双字节，单字节部分只接受 ASCII。汉字区与 GB18030 的双字节区一致，
/// 只是 GBK 不接受其中 2,149 个用户自定义区格子（那些只在 GB18030 里合法）。
class GbkCodec extends DoubleByteCodec {
  const GbkCodec({super.allowInvalid});

  @override
  String get name => 'gbk';

  @override
  DoubleByteLayout get layout => gbkLayout;
}

/// GBK 的共享实例。
const GbkCodec gbk = GbkCodec();
