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

  /// 这个 code unit 后面还跟着一个 code unit 才算一个字符吗（块尾要留住它）。
  ///
  /// 分块编码用：一个字符的原料被切在两块之间时，只拿到前一半不能编。代理对由
  /// `ChunkedEncodeSink` 统一处理（Dart 字符串本身的规则），这个钩子只管「不是代理对、
  /// 但同样两单元一格」的字符 —— 目前只有 Big5-HKSCS 那 4 个组合字符
  /// （`0x8862` → U+00CA U+0304 这类）。
  bool startsTwoUnitChar(int codeUnit) => false;

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
///
/// 解码方向是**真增量**的：`decodeStream(...)`、`decoder.bind(...)`、
/// `stream.transform(codec.decoder)` 每收到一块就把已经能确定的字符吐出去，只有块尾
/// 「首字节后面还没有第二字节」的那一个字节留到下一块再算。严格模式下坏字节可能在
/// 中途抛出，此前已经吐出的文本是完整可信的前缀（不是从中间截断的半个字符），抛错之后
/// 这条流不再产出任何文本。
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

/// 解双字节编码的一段字节，文本写进 [out]，返回消费掉的字节数。
///
/// [holdIncompleteTail] 为 false（整段解码）时，末尾凑不齐的字节按坏字节处理；
/// 为 true（增量解码）时不消费它们、也不报错，把「消费到哪儿」交回去，由
/// [IncrementalDecodeSink] 留到下一个 chunk —— 一个汉字的两字节可能分属两块。
///
/// 文本写进调用方的缓冲、而不是返回字符串：严格模式下这里会抛 [FormatException]，
/// 那时 [out] 里已经装着这段字节里坏字节**之前**解出来的内容，调用方决定要不要交出去
/// （流式解码会交，整段解码抛了就什么都不留）。
///
/// [baseOffset] 会加到报错的偏移上，让流式解码报的是整个流里的绝对位置；[source]
/// 只写进 [FormatException]（流没有一段连续字节可指，流式解码传 null）。
int _decodeDoubles(
  DoubleByteCodec codec,
  List<int> input,
  List<int>? lost,
  Object? source,
  int baseOffset,
  bool holdIncompleteTail,
  StringBuffer out,
) {
  final DoubleByteLayout layout = codec.layout;
  int index = 0;
  while (index < input.length) {
    final int byte = input[index];
    if (byte < 0x80) {
      out.writeCharCode(byte);
      index++;
      continue;
    }
    if (layout.isLead(byte)) {
      if (index + 1 >= input.length) {
        // 首字节后面还没有字节：只有增量解码要等，整段解码到这里就是坏字节
        if (holdIncompleteTail) break;
      } else {
        final int trail = input[index + 1];
        if (layout.isTrail(trail) && layout.writeText(out, byte, trail)) {
          index += 2;
          continue;
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

/// 一个解不出来的字节怎么办：严格模式抛 [FormatException]，宽松模式记下偏移、
/// 补一个 U+FFFD。
///
/// 双字节编码与 GB18030 两条解码循环共用这一处策略，免得两边语义各自漂移。
void writeInvalidByte({
  required String encodingName,
  required bool allowInvalid,
  required StringBuffer out,
  required List<int>? lost,
  required int offset,
  required Object? source,
}) {
  if (!allowInvalid && lost == null) {
    throw FormatException(
      'Invalid $encodingName byte sequence',
      source,
      offset,
    );
  }
  lost?.add(offset);
  out.writeCharCode(0xFFFD);
}

/// 真增量解码的公共骨架：每来一块就解出能确定的部分，只把块尾不完整的序列留着。
///
/// 各编码的分块差异全在传进来的「解一段」函数里（[_decodeDoubles] / `_decodeGb18030`），
/// 这里只负责跨块拼接、绝对偏移和收尾。
///
/// 与 0.1.2 的 `BufferedDecodeSink`（收齐整个流才解）的区别：文本边收边吐，内存只留
/// 块尾那 1~3 个字节，长文件不必整段进内存。
class IncrementalDecodeSink implements Sink<List<int>> {
  IncrementalDecodeSink(this._decodePrefix, this._out);

  /// 解一段：`(字节, 起始绝对偏移, 是否留住不完整的尾巴, 文本写哪儿) → 消费字节数`。
  final int Function(
    List<int> bytes,
    int baseOffset,
    bool hold,
    StringBuffer out,
  ) _decodePrefix;

  final Sink<String> _out;

  /// 上一块末尾还没凑齐的字节（双字节编码最多 1 个，GB18030 四字节形式最多 3 个）。
  List<int> _pending = const <int>[];

  /// [_pending] 第一个字节在整个流里的偏移。
  int _pendingBase = 0;

  bool _closed = false;

  /// 已经报过一次致命错误，后续分块一律丢掉。
  ///
  /// `stream.transform(codec.decoder)` 抛出错误后**上游不会自动取消**：后面的 chunk 照样
  /// 会送进来。而报错时那块字节没被消费掉，`_pending` 还停在报错前的位置，接着解就会拿
  /// 过期的字节拼出本不该存在的字符（实测 `[0x41,0x81]` + `[0x20,0x42]` + `[0x43]` 会在
  /// 报出偏移 1 之后多吐一个「丆」）。所以第一次抛错就停止消费。
  bool _failed = false;

  @override
  void add(List<int> data) {
    if (_closed) throw StateError('add() called after close()');
    if (_failed || data.isEmpty) return;
    // 绝大多数 chunk 不带上一块的尾巴，这时直接就地解，不做拷贝
    final List<int> bytes =
        _pending.isEmpty ? data : <int>[..._pending, ...data];
    final StringBuffer out = StringBuffer();
    final int used;
    try {
      used = _decodePrefix(bytes, _pendingBase, true, out);
    } on FormatException {
      _fail(out);
      rethrow;
    }
    if (out.isNotEmpty) _out.add(out.toString());
    _pendingBase += used;
    _pending = used == bytes.length ? const <int>[] : bytes.sublist(used);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (!_failed && _pending.isNotEmpty) {
      // 流结束了，这几个字节再等也没有下文 —— 按坏字节收尾（严格模式在这里抛）
      final StringBuffer out = StringBuffer();
      try {
        _decodePrefix(_pending, _pendingBase, false, out);
      } on FormatException {
        _fail(out);
        rethrow;
      }
      if (out.isNotEmpty) _out.add(out.toString());
      _pending = const <int>[];
    }
    // 必须关掉下游，否则 Converter.bind 返回的 Stream 永远不结束（会挂住 await）。
    _out.close();
  }

  /// 抛出致命错误时的收尾：坏字节**之前**已经解出来的文本照常交出去（与 `utf8` 解码器
  /// 一致），然后停止消费后续分块。
  void _fail(StringBuffer out) {
    if (out.isNotEmpty) _out.add(out.toString());
    _failed = true;
    _pending = const <int>[];
  }
}

class _DoubleByteDecoder extends Converter<List<int>, String> {
  const _DoubleByteDecoder(this._codec, [this._lost]);

  final DoubleByteCodec _codec;

  /// 非空时开启「宽松解码 + 记录坏字节偏移」，见 [DoubleByteCodec.decodeLossy]。
  final List<int>? _lost;

  @override
  String convert(List<int> input) {
    final StringBuffer out = StringBuffer();
    _decodeDoubles(_codec, input, _lost, input, 0, false, out);
    return out.toString();
  }

  /// 增量解码：`decoder.bind(...)`、`stream.transform(codec.decoder)`、
  /// `Encoding.decodeStream` 的默认实现都走这里。
  ///
  /// 不实现这个方法的话它们会抛 `UnsupportedError`（[Converter] 的默认实现要求它）。
  @override
  Sink<List<int>> startChunkedConversion(Sink<String> sink) =>
      IncrementalDecodeSink(
        (List<int> bytes, int baseOffset, bool hold, StringBuffer out) =>
            _decodeDoubles(_codec, bytes, null, null, baseOffset, hold, out),
        sink,
      );
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

  /// 逐块编码并转发（见 [ChunkedEncodeSink]）。
  @override
  Sink<String> startChunkedConversion(Sink<List<int>> sink) =>
      ChunkedEncodeSink(convert, sink, _codec.layout.startsTwoUnitChar);
}

/// 逐块编码并转发的 sink（编码方向用）。
///
/// 编码块间本来没有状态，唯一的例外是「一个字符占两个 code unit」：补充平面字符的
/// **代理对**（Dart 字符串本身的规则），以及 Big5-HKSCS 那 4 个**组合字符**
/// （`0x8862` → U+00CA U+0304，两码位一格，由 [DoubleByteLayout.startsTwoUnitChar]
/// 判断）。`stream.transform(codec.encoder)` 完全可能把它们切在两块里，所以碰到块尾
/// 是这类「前一半」时，先留一个 code unit 到下一块再一起编。
class ChunkedEncodeSink implements Sink<String> {
  ChunkedEncodeSink(this._convert, this._out, [this._startsTwoUnitChar]);

  final List<int> Function(String) _convert;
  final Sink<List<int>> _out;

  /// 代理对之外「两单元才算一个字符」的判断，见 [DoubleByteLayout.startsTwoUnitChar]。
  final bool Function(int codeUnit)? _startsTwoUnitChar;

  /// 上一块末尾那个还没凑齐的 code unit（最多 1 个）。
  String _pending = '';

  bool _closed = false;

  /// 已经报过一次致命错误，后续分块一律丢掉（理由同 [IncrementalDecodeSink._failed]：
  /// 出错之后上游不会自动停）。
  bool _failed = false;

  @override
  void add(String data) {
    if (_closed) throw StateError('add() called after close()');
    if (_failed) return;
    final String text = _pending.isEmpty ? data : _pending + data;
    _pending = '';
    if (text.isEmpty) return;
    final int last = text.codeUnitAt(text.length - 1);
    // 块尾可能是「一个字符的前一半」：代理对的高位，或 HKSCS 组合字符的第一个码位
    if (last >= 0xD800 && last <= 0xDBFF ||
        (_startsTwoUnitChar?.call(last) ?? false)) {
      _pending = text.substring(text.length - 1);
      // 整块就这半个字符：等下一块，先不编
      if (text.length == 1) return;
      _emit(text.substring(0, text.length - 1));
      return;
    }
    _emit(text);
  }

  void _emit(String text) {
    final List<int> bytes;
    try {
      bytes = _convert(text);
    } on FormatException {
      _failed = true;
      _pending = '';
      rethrow;
    }
    _out.add(bytes);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    // 孤零零的高位代理：与整段编码一致，抛 FormatException（这里让 convert 抛）
    if (!_failed && _pending.isNotEmpty) _emit(_pending);
    _out.close();
  }
}
