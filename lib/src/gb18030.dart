import 'dart:convert';

import 'double_byte_codec.dart'
    show
        ChunkedEncodeSink,
        DecodeReport,
        IncrementalDecodeSink,
        writeInvalidByte;
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
///
/// 解码方向是**真增量**的：`decodeStream(...)`、`decoder.bind(...)`、
/// `stream.transform(codec.decoder)` 每收到一块就把已经能确定的字符吐出去，只有块尾
/// 凑不齐的那 1~3 个字节（四字节形式最多要等三个）留到下一块再算。严格模式下坏字节
/// 可能在中途抛出，此前已经吐出的文本是完整可信的前缀。
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
  /// 粒度是**按字节**：一个非法字节补一个 U+FFFD。一个凑不齐的四字节序列因此会得到
  /// 两三个替换符（中间夹着的 ASCII 不会被吞掉），而不是整段合并成一个。
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

  /// 宽松解码，并把「哪些字节被换成了 U+FFFD」一并报出来。
  ///
  /// 语义与 `DoubleByteCodec.decodeLossy` 相同，只是这里多一种四字节形式：
  /// 一个凑不齐或非法的四字节序列会按字节记 2~3 条偏移（不是合并成一条），
  /// 中间夹着的 ASCII 不会被吞掉。
  ///
  /// **不受 [allowInvalid] 影响**：总是宽松解码。
  DecodeReport decodeLossy(List<int> bytes) {
    final List<int> lostOffsets = <int>[];
    final String text = _Gb18030Decoder(this, lostOffsets).convert(bytes);
    return DecodeReport(text, lostOffsets);
  }

  /// 返回编码名，与 [name] 相同（`gb18030`）。
  @override
  String toString() => name;
}

/// GB18030 的共享实例（严格模式，坏字节抛 [FormatException]）。
const Gb18030Codec gb18030 = Gb18030Codec();

class _Gb18030Decoder extends Converter<List<int>, String> {
  const _Gb18030Decoder(this._codec, [this._lost]);

  final Gb18030Codec _codec;

  /// 非空时开启「宽松解码 + 记录坏字节偏移」，见 [Gb18030Codec.decodeLossy]。
  final List<int>? _lost;

  @override
  String convert(List<int> input) {
    final StringBuffer out = StringBuffer();
    _decodeGb18030(_codec, input, _lost, input, 0, false, out);
    return out.toString();
  }

  /// 增量解码：`decoder.bind(...)`、`stream.transform(codec.decoder)`、
  /// `Encoding.decodeStream` 的默认实现都走这里。
  @override
  Sink<List<int>> startChunkedConversion(Sink<String> sink) =>
      IncrementalDecodeSink(
        (List<int> bytes, int baseOffset, bool hold, StringBuffer out) =>
            _decodeGb18030(_codec, bytes, null, null, baseOffset, hold, out),
        sink,
      );
}

/// 解 GB18030 的一段字节，文本写进 [out]，返回消费掉的字节数。
///
/// [holdIncompleteTail] 为 true（增量解码）时，块尾「还差后面几个字节」的四字节形式
/// 不消费也不报错，交给 [IncrementalDecodeSink] 等下一块；为 false（整段解码）时
/// 一律按坏字节处理。其余参数含义同 `_decodeDoubles`。
int _decodeGb18030(
  Gb18030Codec codec,
  List<int> input,
  List<int>? lost,
  Object? source,
  int baseOffset,
  bool holdIncompleteTail,
  StringBuffer out,
) {
  int index = 0;
  while (index < input.length) {
    final int byte = input[index];
    if (byte < 0x80) {
      out.writeCharCode(byte);
      index++;
      continue;
    }
    if (isLeadByte(byte)) {
      if (index + 1 >= input.length) {
        // 首字节后面还没有字节：只有增量解码要等
        if (holdIncompleteTail) break;
      } else {
        final int second = input[index + 1];
        if (second >= 0x30 && second <= 0x39) {
          // 第二个字节是数字 ⇒ 只能是四字节形式，缺一个字节都算坏序列
          if (index + 2 >= input.length) {
            if (holdIncompleteTail) break; // 第三字节还没来
          } else if (isLeadByte(input[index + 2])) {
            if (index + 3 >= input.length) {
              if (holdIncompleteTail) break; // 第四字节还没来
            } else {
              final int fourth = input[index + 3];
              if (fourth >= 0x30 && fourth <= 0x39) {
                final int? codePoint = gb18030CodePointOfIndex(
                  ((byte - 0x81) * 10 + (second - 0x30)) * 1260 +
                      (input[index + 2] - 0x81) * 10 +
                      (fourth - 0x30),
                );
                if (codePoint != null) {
                  out.writeCharCode(codePoint);
                  index += 4;
                  continue;
                }
              }
            }
          }
          // 第三字节不是首字节 / 第四字节不是数字 / 序号解不出码位：
          // 四字节形式不成立，落到下面的坏字节处理（只消费首字节）
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
    }
    writeInvalidByte(
      encodingName: codec.name,
      allowInvalid: codec.allowInvalid,
      out: out,
      lost: lost,
      offset: baseOffset + index,
      source: source,
    );
    index++;
  }
  return index;
}

class _Gb18030Encoder extends Converter<String, List<int>> {
  const _Gb18030Encoder();

  @override
  List<int> convert(String input) {
    // 用可增长的 List<int>、不用 BytesBuilder：后者逐字节 addByte 实测慢 3 倍
    // （1 MB 文本 11.7 MB/s vs 37.8 MB/s），同门其它编码器也都是 List<int>。
    final List<int> out = <int>[];
    for (final int rune in input.runes) {
      if (rune < 0x80) {
        out.add(rune);
        continue;
      }
      // 双字节优先：同一个字符能两字节表示时，四字节形式不是它的规范写法
      final (int, int)? pair = gb18030DoubleByteLayout.bytesOf(rune);
      if (pair != null) {
        out
          ..add(pair.$1)
          ..add(pair.$2);
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
      out
        ..add(0x81 + index ~/ (10 * 1260))
        ..add(0x30 + (index % (10 * 1260)) ~/ 1260)
        ..add(0x81 + (index % 1260) ~/ 10)
        ..add(0x30 + index % 10);
    }
    return out;
  }

  /// 逐块编码并转发（见 [ChunkedEncodeSink]）。
  @override
  Sink<String> startChunkedConversion(Sink<List<int>> sink) =>
      ChunkedEncodeSink(convert, sink);
}
