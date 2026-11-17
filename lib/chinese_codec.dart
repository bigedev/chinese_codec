/// 中文字符集编解码：GB18030 / GBK / GB2312 / Big5 / Big5-HKSCS，纯 Dart，
/// 无原生依赖。
///
/// `dart:convert` 只有 UTF-8 / Latin-1 / ASCII，遇到老文件（VB、Delphi、Windows 上
/// 存盘的文本）只能报「不是 UTF-8」。这个包补上五种中文编码：
///
/// ```dart
/// import 'package:chinese_codec/chinese_codec.dart';
///
/// final String text = gbk.decode(bytes);       // 严格：坏字节抛 FormatException
/// final List<int> back = gb18030.encode(text); // 编不出来的字符抛 FormatException
/// final String trad = big5.decode(twBytes);    // 繁体（CP950，Windows 常见）
/// final String hk = big5hkscs.decode(hkBytes); // 繁体（香港增补字符集）
/// ```
///
/// 想「尽量读出来」时用带 `allowInvalid` 的实例（坏字节变成 U+FFFD，
/// 与 `utf8.decode(allowMalformed: true)` 同义）：
///
/// ```dart
/// const GbkCodec lenient = GbkCodec(allowInvalid: true);
/// final String text = lenient.decode(bytes);
/// ```
///
/// 想知道「坏在哪」而不只是「读出来了」，用 `decodeLossy` —— 它宽松解码，
/// 并给出每个被替换字节的位置：
///
/// ```dart
/// final DecodeReport report = GbkCodec().decodeLossy(bytes);
/// if (!report.isClean) {
///   print('${report.lostBytes} 个字节解不出来：${report.lostOffsets}');
/// }
/// ```
///
/// ## 这段字节到底是什么编码
///
/// 本包**不猜**：中文编码的字节空间互相重叠，猜错比报错更难查。它给的是三件
/// 确定性的事 —— [tryDecode]（能解吗）、[verifyRoundTrip]（解出来再编回去对不对得上）、
/// [codecsThatRoundTrip]（哪些编码都能对上）。
///
/// ```dart
/// import 'dart:convert';
///
/// final String? utf8Text = tryDecode(bytes, utf8);   // 先试 UTF-8
/// if (utf8Text != null) return utf8Text;
///
/// final List<Encoding> fits = codecsThatRoundTrip(bytes);
/// // 0 条：没有候选能解释它；1 条：证据唯一；多条：真歧义，按业务挑
/// ```
library;

export 'src/big5.dart' show Big5Codec, big5;
export 'src/big5hkscs.dart' show Big5HkscsCodec, big5hkscs;
export 'src/double_byte_codec.dart' show DecodeReport;
export 'src/gb18030.dart' show Gb18030Codec, gb18030;
export 'src/gb2312.dart' show Gb2312Codec, gb2312;
export 'src/gbk.dart' show GbkCodec, gbk;
export 'src/inspect.dart'
    show codecsThatRoundTrip, tryDecode, unrepresentableRunes, verifyRoundTrip;
export 'src/registry.dart' show chineseCodecs, chineseEncodingByName;

/// `dart:convert` 的 [Encoding] 一并导出：写 `List<Encoding>`、判类型时不必再单独
/// `import 'dart:convert'`。
export 'dart:convert' show Encoding;
