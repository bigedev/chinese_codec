import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

  /// 把 [lead]/[trail] 对应的文本写进 [out]，不是合法字符时返回 false。
  ///
  /// 解码热路径走这个方法而不是 [textOf]：默认实现直接用
  /// `writeCharCode(codePointOf(...))`，省掉「每解一个字造一个单字符 String」的
  /// 分配 —— 实测同一个 GBK 文件能快 2.4 倍。需要吐多个码位的
  /// Big5-HKSCS 覆盖它。
  bool writeText(StringBuffer out, int lead, int trail) {
    final int? codePoint = codePointOf(lead, trail);
    if (codePoint == null) return false;
    out.writeCharCode(codePoint);
    return true;
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

/// 纯双字节编码的公共实现：GBK / GB2312 / Big5 / Big5-HKSCS 都是它的子类。
///
/// 这几家共用同一套外层循环 —— ASCII 直通、字节对查表、坏字节按 [allowInvalid]
/// 处理，差异只落在各自 [layout] 的格子空间上。GB18030 多一种四字节形式，
/// 直接实现 [Encoding]，不走这条基类。
///
/// 解码方向：坏字节抛 [FormatException]，[allowInvalid] 为 true 时换成 U+FFFD。
/// 编码方向：字符在该字符集里没有对应格子时**总是**抛 [FormatException]，
/// [allowInvalid] 不影响编码 —— 宽松模式只负责「尽量读出来」，不能凭空造字。
abstract class DoubleByteCodec extends Encoding {
  /// 创建一个编解码实例。
  ///
  /// [allowInvalid] 决定坏字节怎么处理，详见同名字段。
  const DoubleByteCodec({this.allowInvalid = false});

  /// 遇到解不出来的字节时：true 换成 U+FFFD 继续，false 抛 [FormatException]。
  ///
  /// 和 `utf8.decode(allowMalformed:)` 同义。默认严格 —— 拿不准的时候宁可报错，
  /// 也不要把一堆替换字符写回文件。
  ///
  /// 粒度是**按字节**：一个非法字节补一个 U+FFFD，不合并整段坏序列。所以
  /// `[0xA4, 0x20]` 解成「\uFFFD + 空格」，而不是把两个字节一起换掉。
  ///
  /// 只作用于解码；编码方向编不出来的字符总是抛 [FormatException]。
  final bool allowInvalid;

  /// 当前编码的字节映射表：哪些首字节 / 第二字节合法、字节对换成哪个码位。
  ///
  /// 实现细节，日常 `decode` / `encode` 不必接触；只有想自己遍历整张表的工具代码
  /// 才需要它。
  DoubleByteLayout get layout;

  /// 编码器：ASCII 直通，其余字符查表；编不出来的字符抛 [FormatException]。
  @override
  Converter<String, List<int>> get encoder => _DoubleByteEncoder(this);

  /// 解码器：坏字节按 [allowInvalid] 抛 [FormatException] 或换成 U+FFFD。
  @override
  Converter<List<int>, String> get decoder => _DoubleByteDecoder(this);

  /// 把整个字节流读完再解码，结果等同 `decode(整段字节)`。
  ///
  /// 不是增量解码，好处是多字节字符被切在两个 chunk 之间也不受影响。
  /// 内部实现见 [decodeWholeStream]。
  @override
  Future<String> decodeStream(Stream<List<int>> byteStream) =>
      decodeWholeStream(this, byteStream);

  /// 宽松解码，并把「哪些字节被换成了 U+FFFD」一并报出来。
  ///
  /// 与 `GbkCodec(allowInvalid: true).decode(bytes)` 的区别只有一处：那个只会给你
  /// 一串替换符，看不出丢了多少、丢在哪 —— 这个给 [DecodeReport]。
  ///
  /// **不受 [allowInvalid] 影响**：它总是宽松解码（否则坏字节一律抛异常，
  /// 也就无从报告）。批次导入、编码转换这类「先读进来再看坏在哪」的场合用它；
  /// 只要文本、不在乎坏字节时，宽松实例的 `decode` 更省一次记录开销。
  ///
  /// ```dart
  /// const DecodeReport report = GbkCodec().decodeLossy(bytes);
  /// if (!report.isClean) {
  ///   print('${report.lostBytes} 个字节解不出来，位置 ${report.lostOffsets}');
  /// }
  /// ```
  DecodeReport decodeLossy(List<int> bytes) {
    final List<int> lostOffsets = <int>[];
    final String text = _DoubleByteDecoder(this, lostOffsets).convert(bytes);
    return DecodeReport(text, lostOffsets);
  }

  /// 返回编码名，与 [name] 相同（例如 `gbk`）。
  @override
  String toString() => name;
}

/// 宽松解码的结果：文本 + 每个被替换掉的字节位置。
///
/// 由 [DoubleByteCodec.decodeLossy] / `Gb18030Codec.decodeLossy` 产出。替换粒度与
/// `allowInvalid` 一致 —— **按字节**：一个非法字节记一条偏移、补一个 U+FFFD，
/// 所以一个凑不齐的四字节序列会得到 2~3 条偏移（中间夹的 ASCII 不在其中）。
///
/// `text` 里的 U+FFFD 与 `lostOffsets` 一一对应（顺序一致），可以据此把坏字节
/// 定位回原始数据。
class DecodeReport {
  /// 创建一个报告。一般不必自己构造，用 `decodeLossy` 就行。
  const DecodeReport(this.text, this.lostOffsets);

  /// 宽松解码出来的文本：坏字节的位置上是 U+FFFD。
  final String text;

  /// 被替换字节在**输入**里的偏移（升序，0 起）。
  final List<int> lostOffsets;

  /// 丢掉了几个字节（= [lostOffsets] 的长度）。
  int get lostBytes => lostOffsets.length;

  /// 全程没有坏字节 —— 这份报告与严格解码的结果完全一致。
  bool get isClean => lostOffsets.isEmpty;

  @override
  String toString() =>
      'DecodeReport(${text.length} chars, lost $lostBytes bytes)';
}

/// 把 [byteStream] 读完再交给 [codec] 一次性解码。
///
/// `Converter` 的子类没有实现分块转换，`dart:convert` 里 [Encoding.decodeStream]
/// 的默认实现走的正是分块路径（`decoder.bind` → `startChunkedConversion`），
/// 一用就抛 `UnsupportedError`。所以各编码统一覆盖成「先读完再解」。
Future<String> decodeWholeStream(
  Encoding codec,
  Stream<List<int>> byteStream,
) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in byteStream) {
    builder.add(chunk);
  }
  return codec.decode(builder.takeBytes());
}

class _DoubleByteDecoder extends Converter<List<int>, String> {
  const _DoubleByteDecoder(this._codec, [this._lost]);

  final DoubleByteCodec _codec;

  /// 非空时开启「宽松解码 + 记录坏字节偏移」，见 [DoubleByteCodec.decodeLossy]。
  final List<int>? _lost;

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
        if (layout.writeText(out, byte, input[index + 1])) {
          index += 2;
          continue;
        }
      }
      if (!_codec.allowInvalid && _lost == null) {
        throw FormatException(
          'Invalid ${_codec.name} byte sequence',
          input,
          index,
        );
      }
      _lost?.add(index);
      out.writeCharCode(0xFFFD);
      index++;
    }
    return out.toString();
  }

  /// 收齐所有分块后一次性解码，`close()` 时才把结果交给下游。
  ///
  /// 不实现这个方法的话 `decoder.bind(...)`、`stream.transform(codec.decoder)`
  /// 会抛 `UnsupportedError`（`Converter` 的默认实现要求它）。
  @override
  Sink<List<int>> startChunkedConversion(Sink<String> sink) =>
      BufferedDecodeSink(convert, sink);
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

  /// 逐块编码并转发。编码方向块间无状态（一个 chunk 就是一段完整字符串），
  /// 不像解码那样要收齐再算。
  @override
  Sink<String> startChunkedConversion(Sink<List<int>> sink) =>
      PerChunkEncodeSink(convert, sink);
}

/// 把分块字节收齐、`close()` 时一次性转换的 sink（解码方向用）。
///
/// 解码必须这样：一个汉字的两个字节可能分属相邻两个 chunk，逐块解会散架。
/// 它只保证 `decoder.bind(...)` / `transform(codec.decoder)` 能用，**不是**增量
/// 解码 —— 真增量要各自维护 pending 字节，等有需求再说。
class BufferedDecodeSink implements Sink<List<int>> {
  BufferedDecodeSink(this._convert, this._out);

  final String Function(List<int>) _convert;
  final Sink<String> _out;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  void close() {
    _out.add(_convert(_bytes.takeBytes()));
    // 必须关掉下游，否则 Converter.bind 返回的 Stream 永远不结束（会挂住 await）。
    _out.close();
  }
}

/// 逐块转换并转发的 sink（编码方向用）。
class PerChunkEncodeSink implements Sink<String> {
  PerChunkEncodeSink(this._convert, this._out);

  final List<int> Function(String) _convert;
  final Sink<List<int>> _out;

  @override
  void add(String data) => _out.add(_convert(data));

  @override
  void close() => _out.close();
}
