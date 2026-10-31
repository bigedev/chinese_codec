import 'dart:typed_data';

import 'double_byte_codec.dart';
import 'tables.dart';

/// GB 系（GB18030 / GBK / GB2312）的双字节区布局。
///
/// 三者共用同一张最大集表（GB18030 的 23,940 个格子），差异只有两处：
/// 哪些格子收（位图）、少数格子的码位不同（override 表）。
class GbLayout extends DoubleByteLayout {
  const GbLayout({
    required this.validityMask,
    required this.overrides,
    required this.reverseMap,
  });

  /// 该编码接受哪些格子；null 表示全收（GB18030 的双字节区）。
  final Uint8List? validityMask;

  /// 与主表不一致的格子（序号 → 码位）。
  final Map<int, int> overrides;

  /// 码位 → 格子序号。
  final Map<int, int> reverseMap;

  @override
  bool isLead(int byte) => isLeadByte(byte);

  @override
  bool isTrail(int byte) => isTrailByte(byte);

  @override
  int? codePointOf(int lead, int trail) {
    if (!isLeadByte(lead) || !isTrailByte(trail)) return null;
    return doubleByteCodePointAt(
      doubleByteIndexOf(lead, trail),
      validityMask,
      overrides,
    );
  }

  @override
  (int, int)? bytesOf(int codePoint) {
    final int? cell = reverseMap[codePoint];
    if (cell == null) return null;
    return doubleByteBytesOf(cell);
  }
}

/// GBK 的双字节区。
final GbLayout gbkLayout = GbLayout(
  validityMask: gbkValidityMask,
  overrides: const <int, int>{},
  reverseMap: gbkReverseMap,
);

/// GB2312 的双字节区（7,445 个格子，含 2 个 override）。
final GbLayout gb2312Layout = GbLayout(
  validityMask: gb2312ValidityMask,
  overrides: gb2312Overrides,
  reverseMap: gb2312ReverseMap,
);

/// GB18030 的双字节区（最大集，全收）。
final GbLayout gb18030DoubleByteLayout = GbLayout(
  validityMask: null,
  overrides: const <int, int>{},
  reverseMap: gb18030DoubleByteReverseMap,
);
