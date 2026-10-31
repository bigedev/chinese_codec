import 'dart:convert';
import 'dart:typed_data';

import 'tables.g.dart' as generated;

/// 双字节区的格子数：lead 0x81-0xFE（126）× trail 0x40-0xFE 去掉 0x7F（190）。
const int doubleByteCellCount = 23940;

/// GB18030 四字节序列的序号空间：126 × 10 × 126 × 10。
const int gb18030IndexSpace = 126 * 10 * 126 * 10;

/// 双字节表（GB18030 的最大集）：格子序号 → 码位，0 表示不合法。
///
/// 懒加载：只用 GB18030 / GBK 之一的调用方也只付一次 base64 解码的钱。
final Uint16List doubleByteTable =
    decodeUint16Table(generated.doubleByteTableBase64);

/// GBK 接受哪些双字节格子（GBK ⊂ GB18030，差异全是「GBK 不收、GB18030 收」）。
final Uint8List gbkValidityMask = base64.decode(generated.gbkValidityBase64);

/// GB2312 接受哪些双字节格子（7,445 个，真子集）。
final Uint8List gb2312ValidityMask =
    base64.decode(generated.gb2312ValidityBase64);

/// GB2312 与主表不一致的格子（A1A4 是「・」、A1AA 是「―」，见生成脚本）。
final Map<int, int> gb2312Overrides = <int, int>{
  for (int i = 0; i < generated.gb2312Overrides.length; i += 2)
    generated.gb2312Overrides[i]: generated.gb2312Overrides[i + 1],
};

/// 四字节区里「补充平面线性区」的起点（该序号对应 U+10000）。
const int gb18030LinearStart = generated.gb18030LinearStart;

/// BMP 内的四字节映射，按连续段压紧：每 3 个整数是「起始序号、起始码位、长度」。
const List<int> gb18030BmpRuns = generated.gb18030BmpRuns;

/// GBK 的反查表：码位 → 格子序号（只收 GBK 认的格子）。
final Map<int, int> gbkReverseMap = _buildReverseMap(gbkValidityMask, null);

/// GB2312 的反查表：码位 → 格子序号（按 GB2312 自己的映射，含 override）。
final Map<int, int> gb2312ReverseMap =
    _buildReverseMap(gb2312ValidityMask, gb2312Overrides);

/// GB18030 双字节区的反查表：码位 → 格子序号（最大集，无 override）。
final Map<int, int> gb18030DoubleByteReverseMap = _buildReverseMap(null, null);

/// 格子序号 → 码位；该编码不接受这一格时返回 null。
int? doubleByteCodePointAt(
    int index, Uint8List? mask, Map<int, int>? overrides) {
  if (index < 0 || index >= doubleByteCellCount) return null;
  if (mask != null && !_maskBit(mask, index)) return null;
  final int? override = overrides?[index];
  if (override != null) return override;
  final int codePoint = doubleByteTable[index];
  return codePoint == 0 ? null : codePoint;
}

/// 四字节序号 → 码位；序号不落在任何段里时返回 null。
int? gb18030CodePointOfIndex(int index) {
  if (index < 0 || index >= gb18030IndexSpace) return null;
  if (index >= gb18030LinearStart) {
    final int codePoint = 0x10000 + (index - gb18030LinearStart);
    return codePoint > 0x10FFFF ? null : codePoint;
  }
  int low = 0;
  int high = gb18030BmpRuns.length ~/ 3 - 1;
  while (low <= high) {
    final int mid = (low + high) >> 1;
    final int start = gb18030BmpRuns[mid * 3];
    final int length = gb18030BmpRuns[mid * 3 + 2];
    if (index < start) {
      high = mid - 1;
    } else if (index >= start + length) {
      low = mid + 1;
    } else {
      return gb18030BmpRuns[mid * 3 + 1] + (index - start);
    }
  }
  return null;
}

/// 码位 → 四字节序号（只处理 BMP 里需要四字节表示的那部分）；编不出来返回 null。
int? gb18030BmpIndexOf(int codePoint) {
  // 段数只有两百出头，线性扫比维护第二份索引更省事
  for (int i = 0; i < gb18030BmpRuns.length; i += 3) {
    final int start = gb18030BmpRuns[i + 1];
    final int length = gb18030BmpRuns[i + 2];
    if (codePoint >= start && codePoint < start + length) {
      return gb18030BmpRuns[i] + (codePoint - start);
    }
  }
  return null;
}

/// 双字节格子的序号：`(lead - 0x81) * 190 + trail 在行内的偏移`。
int doubleByteIndexOf(int lead, int trail) =>
    (lead - 0x81) * 190 + (trail < 0x7F ? trail - 0x40 : trail - 0x41);

/// 首字节（两个字节里的第一个）。
bool isLeadByte(int byte) => byte >= 0x81 && byte <= 0xFE;

/// 第二字节（跳过 0x7F，它是空的）。
bool isTrailByte(int byte) => byte >= 0x40 && byte <= 0xFE && byte != 0x7F;

/// 由格子序号反推两字节。
(int, int) doubleByteBytesOf(int index) {
  final int lead = 0x81 + index ~/ 190;
  final int offset = index % 190;
  return (lead, offset < 0x3F ? 0x40 + offset : 0x41 + offset);
}

bool _maskBit(Uint8List mask, int index) =>
    (mask[index >> 3] & (1 << (index & 7))) != 0;

/// 把「小端 UInt16 + base64」的表解成 [Uint16List]（Big5 那张表也走这里）。
Uint16List decodeUint16Table(String base64Text) {
  final Uint8List bytes = base64.decode(base64Text);
  final Uint16List table = Uint16List(bytes.length ~/ 2);
  for (int i = 0; i < table.length; i++) {
    table[i] = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
  }
  return table;
}

Map<int, int> _buildReverseMap(Uint8List? mask, Map<int, int>? overrides) {
  final Map<int, int> map = <int, int>{};
  for (int index = 0; index < doubleByteCellCount; index++) {
    final int? codePoint = doubleByteCodePointAt(index, mask, overrides);
    // 同一码位有多个格子时取序号最小的那个（生成表时已按行优先排序）
    if (codePoint != null && !map.containsKey(codePoint)) {
      map[codePoint] = index;
    }
  }
  return map;
}
