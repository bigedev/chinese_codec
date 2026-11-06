import 'dart:convert';
import 'dart:typed_data';

import 'double_byte_codec.dart';
import 'tables.dart' show ReverseCellMap, decodeUint16Table;
import 'tables_big5hkscs.g.dart' as generated;

/// Big5-HKSCS 实际有字的首字节：0x87（0x81-0x86 规范预留、未分配）。
const int hkscsLeadMin = 0x87;

/// Big5-HKSCS 的首字节上限。
const int hkscsLeadMax = 0xFE;

/// 第二字节个数：0x40-0x7E（63 个）+ 0xA1-0xFE（94 个），与 CP950 相同。
const int hkscsTrailCount = 63 + 94;

/// 主表里的哨兵：这一格的内容在附加表里（补充平面字符或组合字符）。
const int hkscsExtendedMark = 0xFFFF;

/// 主表：序号 → 码位，0 表示不合法，[hkscsExtendedMark] 表示查附加表。
final Uint16List hkscsTable = decodeUint16Table(
  generated.hkscsTableBase64,
);

/// 附加表的格子序号（升序）。
final Uint16List hkscsExtendedCells = decodeUint16Table(
  generated.hkscsExtendedCellsBase64,
);

/// 附加表的文本，与 [hkscsExtendedCells] 逐项对应。
final List<String> hkscsExtendedTexts = _decodeExtendedTexts(
  generated.hkscsExtendedTextBase64,
);

/// 格子序号 → 附加表位置。
final Map<int, int> hkscsExtendedCellIndex = <int, int>{
  for (int i = 0; i < hkscsExtendedCells.length; i++) hkscsExtendedCells[i]: i,
};

/// 码位 → 格子序号（BMP 部分）。
///
/// 一批字符在 HKSCS 里占两格：标准 Big5 区（lead 0xA1-0xF9）一格、扩展区
/// （0x87-0xA0）再一格。这里**优先标准区**，因为扩展区的字节 CP950 / Windows 解不
/// 出来（实测「兙」走扩展区写成 `0x92AF`，iconv 的 CP950 直接报错；标准区是
/// `0xA259`）。只取序号最小会选到扩展区那一格 —— 那正是 0.1.1 的行为。
///
/// 标准区没有格子时才退到 0x87-0xA0，最后才是 0xFA-0xFE（CP950 里那是用户自定义区，
/// 别的软件可能往里写过东西）。
final ReverseCellMap hkscsBmpReverseMap = _buildBmpReverseMap();

/// 两个 UTF-16 单元 → 格子序号（附加表部分，键是 `高 16 位 << 16 | 低 16 位`）。
///
/// 补充平面字符天然是代理对，组合字符本来就是两个码位，两者的共同点是
/// 「一个格子出两个 UTF-16 单元」，所以能用同一张反查表。
final Map<int, int> hkscsExtendedReverseMap = _buildExtendedReverseMap();

/// Big5-HKSCS 编解码。
///
/// 双字节，单字节部分只接受 ASCII。等价于 Big5 加香港增补字符集，覆盖 18,594 个
/// 格子：CP950 的那 13,752 格（其中 250 格映射不同）+ 4,842 个 HKSCS 独有格，
/// 含 1,713 个补充平面码位（粤语用字、人名与地名用字）。
///
/// 数据取自 WHATWG Encoding Standard 的 `index-big5.txt`（web 上的 Big5 实现基准，
/// 即 Big5 + HKSCS-2008，18,590 格），再加上规范正文单独定义的 4 个组合字符。
/// CPython 的 `big5hkscs` 有 18,402 格，全部包含在本类里；本类另有 192 格
/// （`0xA3E1` 的「€」等），两边逐格交叉核对过。
///
/// 「全部包含」说的是格子覆盖，**不是逐格同值**：有 11 格标点与 CPython / glibc 的
/// `big5hkscs` 结果不同（例如 `0xA145` 这里是「‧」U+2027、glibc 给「•」U+2022），
/// 这 11 格与 CP950 一致，也就是和 WHATWG / 浏览器一致。要与 glibc 逐字节对齐的
/// 调用方需要自己知道这个差异。
///
/// **与 [Big5Codec]（CP950）不是包含关系**：格子是它的超集（CP950 的 13,752 格
/// 全都在），但 250 格映射不同 —— HKSCS 把 ETen 扩展的假名、俄文、希腊字母区
/// （0xC6A1-0xC8FE 等）拿去放汉字与带圈数字了，例如 `0xC6A1` 在 CP950 是「ヾ」、
/// 在 HKSCS 是「①」。所以拿 HKSCS 去解一段 CP950 文本，这 250 格的字会变；
/// 反过来 HKSCS 文本在 CP950 下会直接报错。要读 Windows 繁体文件用 [Big5Codec]。
///
/// 编码方向对「同字占两格」的字符有偏好：**优先标准 Big5 区（lead 0xA1-0xF9）
/// 那一格**，扩展区的格子只在没得选时才用。否则写出去的字节 CP950 / Windows 打不开
/// （详见 [hkscsBmpReverseMap]）。
///
/// 四格是「一个字节对换两个码位」的组合字符（`0x8862` → U+00CA U+0304 等），
/// 解码得到两个字符，编码时按这两个码位的组合整体匹配、仍编回同一格。
class Big5HkscsCodec extends DoubleByteCodec {
  /// 创建一个 Big5-HKSCS 编解码实例。
  ///
  /// [allowInvalid] 决定解码时坏字节怎么处理，详见同名字段。
  const Big5HkscsCodec({super.allowInvalid});

  /// 编码名，固定为 `'big5-hkscs'`（带连字符，全小写）。
  ///
  /// 与 `toString()` 的返回值一致，也是下面 [big5hkscs] 实例在 `chineseCodecs` 里的名字。
  @override
  String get name => 'big5-hkscs';

  /// Big5-HKSCS 的字节映射表。
  ///
  /// 首字节 0x87-0xFE（0x81-0x86 规范预留、未分配）× 157 个第二字节；
  /// 主表里放不下的补充平面字符与组合字符记在主表的哨兵位，
  /// 真正内容在附加表，按格子序号回查。
  @override
  DoubleByteLayout get layout => big5HkscsLayout;
}

/// Big5-HKSCS 的共享实例（严格模式，坏字节抛 [FormatException]）。
const Big5HkscsCodec big5hkscs = Big5HkscsCodec();

/// Big5-HKSCS 的字节映射表。
final Big5HkscsLayout big5HkscsLayout = Big5HkscsLayout();

/// Big5-HKSCS 的双字节区布局。
class Big5HkscsLayout extends DoubleByteLayout {
  const Big5HkscsLayout();

  @override
  bool isLead(int byte) => byte >= hkscsLeadMin && byte <= hkscsLeadMax;

  @override
  bool isTrail(int byte) =>
      (byte >= 0x40 && byte <= 0x7E) || (byte >= 0xA1 && byte <= 0xFE);

  @override
  String? textOf(int lead, int trail) {
    if (!isLead(lead) || !isTrail(trail)) return null;
    final int index = _indexOf(lead, trail);
    final int cell = hkscsTable[index];
    if (cell == 0) return null;
    if (cell != hkscsExtendedMark) return String.fromCharCode(cell);
    final int? position = hkscsExtendedCellIndex[index];
    return position == null ? null : hkscsExtendedTexts[position];
  }

  @override
  bool writeText(StringBuffer out, int lead, int trail) {
    if (!isLead(lead) || !isTrail(trail)) return false;
    final int index = _indexOf(lead, trail);
    final int cell = hkscsTable[index];
    if (cell == 0) return false;
    if (cell != hkscsExtendedMark) {
      out.writeCharCode(cell);
      return true;
    }
    final int? position = hkscsExtendedCellIndex[index];
    if (position == null) return false;
    // 组合字符（一格两个码位）与补充平面（代理对）都得整串写
    out.write(hkscsExtendedTexts[position]);
    return true;
  }

  @override
  int? codePointOf(int lead, int trail) {
    final String? text = textOf(lead, trail);
    if (text == null) return null;
    // 组合字符一格出两个码位，没有单一码位可返回
    final List<int> runes = text.runes.toList(growable: false);
    return runes.length == 1 ? runes.first : null;
  }

  @override
  (int, int)? bytesOf(int codePoint) {
    final int? cell = hkscsBmpReverseMap[codePoint];
    return cell == null ? null : _bytesOfIndex(cell);
  }

  @override
  ((int, int), int)? matchAt(String input, int index) {
    // 先试「两个 UTF-16 单元一格」：补充平面字符与组合字符都在附加表里
    if (index + 1 < input.length) {
      final int key =
          (input.codeUnitAt(index) << 16) | input.codeUnitAt(index + 1);
      final int? cell = hkscsExtendedReverseMap[key];
      if (cell != null) return (_bytesOfIndex(cell), 2);
    }
    return super.matchAt(input, index);
  }

  int _indexOf(int lead, int trail) => _indexOfBytes(lead, trail);

  (int, int) _bytesOfIndex(int index) {
    final int lead = hkscsLeadMin + index ~/ hkscsTrailCount;
    final int offset = index % hkscsTrailCount;
    return (lead, offset < 63 ? 0x40 + offset : 0xA1 + offset - 63);
  }
}

List<String> _decodeExtendedTexts(String base64Text) {
  final Uint8List bytes = base64.decode(base64Text);
  final List<String> texts = <String>[];
  for (int i = 0; i + 3 < bytes.length; i += 4) {
    texts.add(String.fromCharCodes(<int>[
      bytes[i] | (bytes[i + 1] << 8),
      bytes[i + 2] | (bytes[i + 3] << 8),
    ]));
  }
  return texts;
}

/// 标准 Big5 区（lead 0xA1-0xF9）在表里的下标区间。
///
/// 编码时的优先级就按这三段排：标准区 → HKSCS 早期的 0x87-0xA0 → 0xFA-0xFE。
/// 最后一段在 CP950 里是「用户自定义区」，别的软件可能往里写过私货，能不用就不用；
/// 这个顺序也和 glibc / CPython 的 `big5hkscs` 一致。
const int _canonicalStart = (0xA1 - hkscsLeadMin) * hkscsTrailCount;
const int _canonicalEnd = (0xFA - hkscsLeadMin) * hkscsTrailCount;

/// 与 CP950 相同：「十」「卅」的规范格不是序号最小那格（同 `big5.dart` 的
/// `big5CanonicalCells`）。HKSCS 里这两个字也各占两格，编码时同样用规范格。
const Map<int, int> hkscsCanonicalCells = <int, int>{
  0x5341: 0xA451, // 十
  0x5345: 0xA4CA, // 卅
};

int _indexOfBytes(int lead, int trail) =>
    (lead - hkscsLeadMin) * hkscsTrailCount +
    (trail < 0x7F ? trail - 0x40 : trail - 0xA1 + 63);

ReverseCellMap _buildBmpReverseMap() {
  final ReverseCellMap map = ReverseCellMap();
  // 三遍，顺序决定编码时用哪一格：标准 Big5 区 → 0x87-0xA0 → 0xFA-0xFE。
  for (int index = _canonicalStart; index < _canonicalEnd; index++) {
    _putBmpCell(map, index);
  }
  for (int index = 0; index < _canonicalStart; index++) {
    _putBmpCell(map, index);
  }
  for (int index = _canonicalEnd; index < hkscsTable.length; index++) {
    _putBmpCell(map, index);
  }
  // 规范格覆盖（序号不是最小的那两格，见 hkscsCanonicalCells）。
  hkscsCanonicalCells.forEach((int codePoint, int bytes) {
    map.put(codePoint, _indexOfBytes(bytes >> 8, bytes & 0xFF));
  });
  return map;
}

void _putBmpCell(ReverseCellMap map, int index) {
  final int cell = hkscsTable[index];
  if (cell != 0 && cell != hkscsExtendedMark && map[cell] == null) {
    map.put(cell, index);
  }
}

Map<int, int> _buildExtendedReverseMap() {
  final Map<int, int> map = <int, int>{};
  for (int i = 0; i < hkscsExtendedCells.length; i++) {
    final String text = hkscsExtendedTexts[i];
    final int key = (text.codeUnitAt(0) << 16) | text.codeUnitAt(1);
    map.putIfAbsent(key, () => hkscsExtendedCells[i]);
  }
  return map;
}
