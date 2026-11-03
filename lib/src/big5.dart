import 'dart:typed_data';

import 'double_byte_codec.dart';
import 'tables.dart';
import 'tables.g.dart' as generated;

/// Big5 的首字节范围：0xA1-0xF9（89 个）。
const int big5LeadMin = 0xA1;

/// 首字节个数。
const int big5LeadCount = 0xF9 - 0xA1 + 1;

/// 第二字节个数：0x40-0x7E（63 个）+ 0xA1-0xFE（94 个）。
const int big5TrailCount = 63 + 94;

/// Big5 双字节表：序号 → 码位，0 表示不合法。
final Uint16List big5Table = decodeUint16Table(generated.big5TableBase64);

/// 码位 → 序号。CP950 里有 10 个码位被两个格子重复映射，取序号最小的那个
/// （编码时给出稳定结果；解码那两个格子都能读出同一个字）。
final Map<int, int> big5ReverseMap = _buildReverseMap();

/// Big5（CP950）编解码。
///
/// 双字节，单字节部分只接受 ASCII。首字节 0xA1-0xF9，第二字节 0x40-0x7E 与
/// 0xA1-0xFE —— 与 GB 系（0x81-0xFE × 190）的格子空间不同，所以序号公式也另算。
///
/// **实现的是 CP950**（Windows 繁体中文的实际上限）：它比经典 Big5 多 42 个格子
/// （例如 `0xA3E1` 是「€」）、另有 11 个格子映射到不同码位。Windows 存的繁体文件
/// 基本都是这个变体。
///
/// 香港的 Big5-HKSCS 在 [Big5HkscsCodec]：它与 CP950 不是包含关系，250 格映射不同，
/// 读 HKSCS 文件要用那一个。
class Big5Codec extends DoubleByteCodec {
  /// 创建一个 Big5（CP950）编解码实例。
  ///
  /// [allowInvalid] 决定解码时坏字节怎么处理，详见同名字段。
  const Big5Codec({super.allowInvalid});

  /// 编码名，固定为 `'big5'`。
  ///
  /// 与 `toString()` 的返回值一致，也是下面 [big5] 实例在 `chineseCodecs` 里的名字。
  @override
  String get name => 'big5';

  /// Big5（CP950）的字节映射表：首字节 0xA1-0xF9（89 个）× 157 个第二字节。
  @override
  DoubleByteLayout get layout => big5Layout;
}

/// Big5 的共享实例（严格模式，坏字节抛 [FormatException]）。
const Big5Codec big5 = Big5Codec();

/// Big5 的字节映射表。
final Big5Layout big5Layout = Big5Layout();

/// Big5 的双字节区布局。
class Big5Layout extends DoubleByteLayout {
  const Big5Layout();

  @override
  bool isLead(int byte) => byte >= big5LeadMin && byte <= 0xF9;

  @override
  bool isTrail(int byte) =>
      (byte >= 0x40 && byte <= 0x7E) || (byte >= 0xA1 && byte <= 0xFE);

  @override
  int? codePointOf(int lead, int trail) {
    if (!isLead(lead) || !isTrail(trail)) return null;
    final int codePoint = big5Table[_indexOf(lead, trail)];
    return codePoint == 0 ? null : codePoint;
  }

  @override
  (int, int)? bytesOf(int codePoint) {
    final int? cell = big5ReverseMap[codePoint];
    if (cell == null) return null;
    final int lead = big5LeadMin + cell ~/ big5TrailCount;
    final int offset = cell % big5TrailCount;
    return (lead, offset < 63 ? 0x40 + offset : 0xA1 + offset - 63);
  }

  int _indexOf(int lead, int trail) =>
      (lead - big5LeadMin) * big5TrailCount +
      (trail < 0x7F ? trail - 0x40 : trail - 0xA1 + 63);
}

Map<int, int> _buildReverseMap() {
  final Map<int, int> map = <int, int>{};
  for (int index = 0; index < big5Table.length; index++) {
    final int codePoint = big5Table[index];
    if (codePoint != 0 && !map.containsKey(codePoint)) {
      map[codePoint] = index;
    }
  }
  return map;
}
