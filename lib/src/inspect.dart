/// 编码「体检」：严格试解、回环校验、按回环结果列出候选编码。
///
/// 本包**不做编码猜测** —— 中文编码的字节空间互相重叠，猜错比报错更难查
/// （见 README 的 Known limitations）。这里给的是三件确定性的事：
///
/// - [tryDecode]：解不出来就返回 null，不抛异常；
/// - [verifyRoundTrip]：解出来的文本再编回去，字节逐位相同才算「这段字节合法且自洽」；
/// - [codecsThatRoundTrip]：把结构上说得通的编码列出来。
///
/// 典型用法是 README 一直推荐、但此前要调用方自己写的那条路：
/// UTF-8 优先，然后试中文编码并用回环校验确认。
///
/// ```dart
/// import 'dart:convert';
/// import 'package:chinese_codec/chinese_codec.dart';
///
/// String readLegacy(List<int> bytes) {
///   final String? utf8Text = tryDecode(bytes, utf8);
///   if (utf8Text != null) return utf8Text;
///
///   // 简体站点取 GB 系、繁体站点取 Big5 系，顺序由业务决定 —— 回环校验
///   // 不会替你区分简繁（见 codecsThatRoundTrip 的说明）。
///   final List<Encoding> fits = codecsThatRoundTrip(bytes);
///   if (fits.isEmpty) throw const FormatException('不是任何中文编码');
///   return fits.first.decode(bytes);
/// }
/// ```
library;

import 'dart:convert';

import 'registry.dart';

/// 严格解码：成功返回文本，遇到非法字节返回 null（不抛异常）。
///
/// 与 `encoding.decode(bytes)` 的唯一差别是「坏字节不抛」——所以它适合
/// 「先试一下」的场合：判断一个文件到底是不是 UTF-8、这段字节能不能按 Big5 读。
///
/// **语义跟随传入的实例**：传共享的严格实例（`gbk` / `gb18030` / `big5` …）时，
/// 坏字节让结果变成 null；传 `GbkCodec(allowInvalid: true)` 时，坏字节照旧换成
/// U+FFFD（那是实例本身的约定），只有真正抛 [FormatException] 的情况才会是 null。
/// 要「只判断能不能解」，请传严格实例。
String? tryDecode(List<int> bytes, Encoding encoding) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// 回环校验：`decode` 之后再 `encode`，字节逐位相同才算通过。
///
/// 它回答的是「这段字节按这个编码解、再编回去还一样吗」，即**结构上合法且自洽**：
///
/// - 通过：字节全在映射表里，解出来的字符编回去是同一对字节；
/// - 不通过：有字节构不成合法字符（截断、超出码位空间），或者命中了「非规范格」
///   —— Big5（CP950）把 `十`（`0xA451`）和 `卅`（`0xA4CA`）各映射了两个格子，
///   编码一律写规范格，字节里若用的另一个格子，回环就不同（文本仍是对的）。
///
/// **它不判断语义，这是最容易误用的一点。** 一段 GBK 简体文本按 Big5 解会得到
/// 一串合法但错误的字（`中文` → `笢恅`），而**回环照样通过** —— 所以回环校验
/// 不能用来自动区分简体与繁体。中文编码的字节空间本来就重叠，想区分只能靠字频
/// 之类的启发式判断，那是调用方的业务决定（见 [codecsThatRoundTrip]）。
///
/// 性能：解码 + 编码各一遍，大文件是两倍开销；只问「能不能解」时用 [tryDecode]。
bool verifyRoundTrip(List<int> bytes, Encoding encoding) {
  final String? text = tryDecode(bytes, encoding);
  if (text == null) {
    return false;
  }
  final List<int> back;
  try {
    back = encoding.encode(text);
  } on FormatException {
    // 解得出、编不回：典型是 HKSCS 扩展区里那 250 个与 CP950 冲突的格子之一。
    return false;
  }
  if (back.length != bytes.length) {
    return false;
  }
  for (int i = 0; i < bytes.length; i++) {
    if (back[i] != bytes[i]) {
      return false;
    }
  }
  return true;
}

/// 所有能通过 [verifyRoundTrip] 的编码，顺序与 [candidates] 一致。
///
/// [candidates] 缺省是 [chineseCodecs]。返回的是**候选清单，不是答案**：
///
/// - **0 条**：没有任何候选能解释这段字节 —— 截断的文件、别的字符集、二进制；
/// - **多条**：结构上都说得通，而且**这是常态**。简体的 GB2312 ⊂ GBK ⊂ GB18030
///   是包含关系；更要紧的是 Big5 与 GB 系的字节空间也重叠 —— 2026-11-17 实测，
///   `中文` 的 GBK 字节 `[0xD6,0xD0,0xCE,0xC4]` 让五种编码**全部**通过回环
///   （Big5 那边解成 `笢恅`）。
///
/// 它真正有确定性的场合只有三种：
///
/// - 出现 **GB18030 四字节序列**时，只有 `gb18030` 能通过（其余四个不认四字节形式）；
/// - 出现 **GB2312 装不下的字**时，`gb2312` 会被排除（例如 `[0x9D, 0xB7]`）；
/// - 文件**根本不是文本**时，一条都不剩。
///
/// 空输入返回空列表：「没有字节」不构成任何证据，不能因此认定五种编码都成立。
///
/// 性能：每个候选各跑一遍 [verifyRoundTrip]，缺省 5 个候选 = 10 遍转换；
/// 大文件建议只取前若干 KB 判断，或先用 [tryDecode] 缩小范围。
List<Encoding> codecsThatRoundTrip(
  List<int> bytes, {
  Iterable<Encoding>? candidates,
}) {
  if (bytes.isEmpty) {
    return const <Encoding>[];
  }
  final List<Encoding> fits = <Encoding>[];
  for (final Encoding encoding in candidates ?? chineseCodecs) {
    if (verifyRoundTrip(bytes, encoding)) {
      fits.add(encoding);
    }
  }
  return fits;
}

/// [text] 里有哪些字符是 [encoding] 表示不了的（返回码位，按出现顺序去重前的原序）。
///
/// `encoding.encode(text)` 遇到第一个编不出来的字符就抛 [FormatException]，
/// 只能告诉你「存不了」，说不出「哪些字存不了」。导出归档文件、把库里的文本落成
/// GB2312 / Big5 时，调用方要的是完整清单：
///
/// ```dart
/// final List<int> missing = unrepresentableRunes(text, gb2312);
/// if (missing.isNotEmpty) {
///   print('GB2312 装不下 ${missing.length} 个字符：'
///       '${missing.map((int r) => String.fromCharCode(r)).join()}');
/// }
/// ```
///
/// 已出现的字符重复出现就重复列出（不去重）——「出现 37 次却只报 1 个」会让人
/// 误判严重程度。需要去重时自己 `toSet()`。
///
/// **一个已知误报**：Big5-HKSCS 有 4 个格子是「一个字节对换两个码位」的组合字符
/// （如 `0x8862` → U+00CA + U+0304）。逐码位检查时单独编 U+00CA 会失败，于是被
/// 列进结果，但整串文本其实存得下。要用在这种文本上时，以 `encode` 整体尝试为准。
///
/// 性能：逐码位调用一次 `encode`，长文本是 O(n) 次转换；只在导出/落盘前跑一次，
/// 不必放进热路径。
List<int> unrepresentableRunes(String text, Encoding encoding) {
  final List<int> missing = <int>[];
  for (final int rune in text.runes) {
    try {
      encoding.encode(String.fromCharCode(rune));
    } on FormatException {
      missing.add(rune);
    }
  }
  return missing;
}
