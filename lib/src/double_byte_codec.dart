import 'dart:convert';

/// 「字节对 ↔ 码位」的映射，双字节编码的差异全在这里。
///
/// 三种编码的码位空间互不相同（GB 系是 lead 0x81-0xFE × 190 个 trail，Big5 是
/// lead 0xA1-0xF9 × 157 个 trail），所以序号公式不能共用；共用的是外层循环：
/// ASCII 直通、字节对查表、坏字节按严格/宽松处理。
abstract class DoubleByteLayout {
  const DoubleByteLayout();

  /// 这个字节可以当首字节吗。
  bool isLead(int byte);

  /// 这个字节可以当第二字节吗。
  bool isTrail(int byte);

  /// 字节对对应的码位；不是合法字符返回 null。
  int? codePointOf(int lead, int trail);

  /// 码位对应的字节对；该字符集里编不出来返回 null。
  (int, int)? bytesOf(int codePoint);

  /// 字节对解出来的文本；不是合法字符返回 null。
  ///
  /// 默认是「一格一个码位」。Big5-HKSCS 有四格是一个字节对换两个码位的组合字符
  /// （`0x8862` → U+00CA U+0304），那里覆盖这个方法。
  String? textOf(int lead, int trail) {
    final int? codePoint = codePointOf(lead, trail);
    return codePoint == null ? null : String.fromCharCode(codePoint);
  }

  /// 从 [input] 的 [index] 开始匹配一个字符，返回（字节对，消耗的 UTF-16 长度）。
  ///
  /// 默认一个码位一格。组合字符要一次吃掉两个码位才能在编码方向往返，
  /// 所以留给 layout 这个钩子。
  ((int, int), int)? matchAt(String input, int index) {
    final int rune = _codePointAt(input, index);
    final (int, int)? bytes = bytesOf(rune);
    if (bytes == null) return null;
    return (bytes, rune > 0xFFFF ? 2 : 1);
  }
}

/// 纯双字节编码的公共实现。
abstract class DoubleByteCodec extends Encoding {
  const DoubleByteCodec({this.allowInvalid = false});

  /// 遇到解不出来的字节时：true 换成 U+FFFD 继续，false 抛 [FormatException]。
  ///
  /// 和 `utf8.decode(allowMalformed:)` 同义。默认严格 —— 拿不准的时候宁可报错，
  /// 也不要把一堆替换字符写回文件。
  final bool allowInvalid;

  /// 当前编码的字节映射表。
  DoubleByteLayout get layout;

  @override
  Converter<String, List<int>> get encoder => _DoubleByteEncoder(this);

  @override
  Converter<List<int>, String> get decoder => _DoubleByteDecoder(this);

  @override
  String toString() => name;
}

class _DoubleByteDecoder extends Converter<List<int>, String> {
  const _DoubleByteDecoder(this._codec);

  final DoubleByteCodec _codec;

  @override
  String convert(List<int> input) {
    final DoubleByteLayout layout = _codec.layout;
    final StringBuffer out = StringBuffer();
    int index = 0;
    while (index < input.length) {
      final int byte = input[index];
      if (byte < 0x80) {
        out.writeCharCode(byte);
        index++;
        continue;
      }
      if (index + 1 < input.length &&
          layout.isLead(byte) &&
          layout.isTrail(input[index + 1])) {
        final String? text = layout.textOf(byte, input[index + 1]);
        if (text != null) {
          out.write(text);
          index += 2;
          continue;
        }
      }
      if (!_codec.allowInvalid) {
        throw FormatException(
          'Invalid ${_codec.name} byte sequence',
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

/// 取 [index] 处的码位（代理对合成一个）。`String` 没有现成的按索引取码位的 API。
int _codePointAt(String input, int index) {
  final int unit = input.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < input.length) {
    final int next = input.codeUnitAt(index + 1);
    if (next >= 0xDC00 && next <= 0xDFFF) {
      return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
    }
  }
  return unit;
}

class _DoubleByteEncoder extends Converter<String, List<int>> {
  const _DoubleByteEncoder(this._codec);

  final DoubleByteCodec _codec;

  @override
  List<int> convert(String input) {
    final DoubleByteLayout layout = _codec.layout;
    final List<int> out = <int>[];
    int index = 0;
    while (index < input.length) {
      final int rune = _codePointAt(input, index);
      if (rune < 0x80) {
        out.add(rune);
        index++;
        continue;
      }
      final ((int, int), int)? match = layout.matchAt(input, index);
      if (match == null) {
        throw FormatException(
          'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
          'is not representable in ${_codec.name}',
        );
      }
      final (int, int) bytes = match.$1;
      out
        ..add(bytes.$1)
        ..add(bytes.$2);
      index += match.$2;
    }
    return out;
  }
}
