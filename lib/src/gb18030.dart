import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'double_byte_codec.dart' show decodeWholeStream;
import 'gb_layout.dart';
import 'tables.dart';

/// GB18030 编解码（含 1 / 2 / 4 字节三种形式）。
///
/// - 单字节：ASCII；
/// - 双字节：与 GBK 同一张表，但**接受 GBK 不认的用户自定义区**（2,149 个格子，
///   落在 PUA），所以同一个文件的 GB18030 结果可能比 GBK 宽一点；
/// - 四字节：BMP 内 GBK 覆盖不到的字符（206 段连续映射，见生成脚本），
///   以及补充平面 U+10000..U+10FFFF 的线性映射。
///
/// 映射按 **GB18030-2022**（含附录 D 表 D.1 的 19 组码位互换）：10 个竖排标点、
/// 8 个汉字构件、以及 U+1E3F 与 PUA U+E7C7 的那一组，双字节格子与四字节序列上的
/// 码位互换，与 ICU 的 `gb18030-2022.ucm` 逐条核对过。
///
/// 与 CPython 的 `gb18030`（2000 / 2005 版）在这 19 组上结果不同：同一段字节在新旧
/// 实现下分别是「真字符」和「PUA」。与 ICU 也有一处**有意分歧**：ICU 把那 18 个
/// 四字节序列标成忽略，老文件里它们会解不出来；本包按国标做完整互换，它们仍解成
/// 原来的 PUA 码位，往返也保得住。
class Gb18030Codec extends Encoding {
  /// 创建一个 GB18030 编解码实例。
  ///
  /// [allowInvalid] 决定解码时坏字节怎么处理，详见同名字段。
  const Gb18030Codec({this.allowInvalid = false});

  /// 遇到解不出来的字节时：true 换成 U+FFFD 继续，false 抛 [FormatException]。
  ///
  /// 和 `utf8.decode(allowMalformed:)` 同义。默认严格 —— 拿不准的时候宁可报错，
  /// 也不要把一堆替换字符写回文件。
  ///
  /// 只作用于解码；编码方向编不出来的字符总是抛 [FormatException]。
  final bool allowInvalid;

  /// 编码名，固定为 `'gb18030'`。
  ///
  /// 与 `toString()` 的返回值一致，也是下面 [gb18030] 实例在 `chineseCodecs` 里的名字。
  @override
  String get name => 'gb18030';

  /// 编码器：双字节区能表示的写两字节，其余走四字节；编不出来的字符抛
  /// [FormatException]。
  @override
  Converter<String, List<int>> get encoder => const _Gb18030Encoder();

  /// 解码器：按第二个字节区分双字节与四字节形式，坏字节按 [allowInvalid]
  /// 抛 [FormatException] 或换成 U+FFFD。
  @override
  Converter<List<int>, String> get decoder => _Gb18030Decoder(this);

  /// 把整个字节流读完再解码，结果等同 `decode(整段字节)`。
  ///
  /// 不是增量解码，好处是多字节字符被切在两个 chunk 之间也不受影响。
  /// 内部实现见 [decodeWholeStream]。
  @override
  Future<String> decodeStream(Stream<List<int>> byteStream) =>
      decodeWholeStream(this, byteStream);

  /// 返回编码名，与 [name] 相同（`gb18030`）。
  @override
  String toString() => name;
}

/// GB18030 的共享实例（严格模式，坏字节抛 [FormatException]）。
const Gb18030Codec gb18030 = Gb18030Codec();

class _Gb18030Decoder extends Converter<List<int>, String> {
  const _Gb18030Decoder(this._codec);

  final Gb18030Codec _codec;

  @override
  String convert(List<int> input) {
    final StringBuffer out = StringBuffer();
    int index = 0;
    while (index < input.length) {
      final int byte = input[index];
      if (byte < 0x80) {
        out.writeCharCode(byte);
        index++;
        continue;
      }
      if (isLeadByte(byte) && index + 1 < input.length) {
        final int second = input[index + 1];
        if (second >= 0x30 && second <= 0x39) {
          // 第二个字节是数字 ⇒ 必须是四字节，后面接不上就算坏序列
          if (index + 3 < input.length) {
            final int third = input[index + 2];
            final int fourth = input[index + 3];
            if (isLeadByte(third) && fourth >= 0x30 && fourth <= 0x39) {
              final int? codePoint = gb18030CodePointOfIndex(
                ((byte - 0x81) * 10 + (second - 0x30)) * 1260 +
                    (third - 0x81) * 10 +
                    (fourth - 0x30),
              );
              if (codePoint != null) {
                out.writeCharCode(codePoint);
                index += 4;
                continue;
              }
            }
          }
        } else if (gb18030DoubleByteLayout.isTrail(second)) {
          final int? codePoint =
              gb18030DoubleByteLayout.codePointOf(byte, second);
          if (codePoint != null) {
            out.writeCharCode(codePoint);
            index += 2;
            continue;
          }
        }
      }
      if (!_codec.allowInvalid) {
        throw FormatException(
          'Invalid gb18030 byte sequence',
          input,
          index,
        );
      }
      out.writeCharCode(0xFFFD);
      index++;
    }
    return out.toString();
  }
}

class _Gb18030Encoder extends Converter<String, List<int>> {
  const _Gb18030Encoder();

  @override
  List<int> convert(String input) {
    final BytesBuilder out = BytesBuilder(copy: false);
    for (final int rune in input.runes) {
      if (rune < 0x80) {
        out.addByte(rune);
        continue;
      }
      // 双字节优先：同一个字符能两字节表示时，四字节形式不是它的规范写法
      final (int, int)? pair = gb18030DoubleByteLayout.bytesOf(rune);
      if (pair != null) {
        out
          ..addByte(pair.$1)
          ..addByte(pair.$2);
        continue;
      }
      final int? index = rune >= 0x10000
          ? (gb18030LinearStart + (rune - 0x10000) < gb18030IndexSpace
              ? gb18030LinearStart + (rune - 0x10000)
              : null)
          : gb18030BmpIndexOf(rune);
      if (index == null) {
        throw FormatException(
          'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
          'is not representable in gb18030',
        );
      }
      out.addByte(0x81 + index ~/ (10 * 1260));
      out.addByte(0x30 + (index % (10 * 1260)) ~/ 1260);
      out.addByte(0x81 + (index % 1260) ~/ 10);
      out.addByte(0x30 + index % 10);
    }
    return out.takeBytes();
  }
}
