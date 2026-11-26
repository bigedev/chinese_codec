import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chinese_codec/chinese_codec.dart';

/// 从一段「不知道是什么编码」的字节里读出文本。
///
/// 顺序就是 README 推荐的：先试 UTF-8，再试中文编码并用回环校验确认。
/// 注意 `fits` 在多数字节序列上会有好几条（中文编码的字节空间互相重叠，
/// 简体文本按 Big5 也能解出一串合法错字），所以这里用「候选顺序」做优先级，
/// 而不是假装能自动判断简繁。
String readLegacyBytes(List<int> bytes) {
  final String? utf8Text = tryDecode(bytes, utf8);
  if (utf8Text != null) {
    return utf8Text;
  }
  final List<Encoding> fits = codecsThatRoundTrip(bytes);
  if (fits.isEmpty) {
    throw const FormatException('既不是 UTF-8，也不是任何中文编码');
  }
  print('  候选编码：${fits.map((Encoding e) => e.name).join(' / ')}');
  return fits.first.decode(bytes);
}

/// 导出前确认目标编码装得下全部字符。
void checkExportable(String text, Encoding target) {
  final List<int> missing = unrepresentableRunes(text, target);
  if (missing.isEmpty) {
    print('  ${target.name} 可以完整表示这段文本');
    return;
  }
  final String chars = missing.map((int r) => String.fromCharCode(r)).join();
  print('  ${target.name} 装不下 ${missing.length} 个字符：$chars');
}

Future<void> main() async {
  // ---- 1. 基本编解码 ----
  print('\n[1] 基本编解码：');

  // 「中文」在 GBK / GB18030 / GB2312 下都是这两个双字节
  const List<int> simplified = <int>[0xd6, 0xd0, 0xce, 0xc4];
  print(gbk.decode(simplified)); // 中文
  print(gbk.encode('中文')); // [214, 208, 206, 196]

  // 同一个词在 Big5（CP950）下是另一套字节
  print(big5.decode(<int>[0xa4, 0xa4, 0xa4, 0xe5])); // 中文

  // 香港增补字符集：CP950 读不了扩展区，Big5-HKSCS 能
  print(big5hkscs.decode(<int>[0x9d, 0xb7])); // 𣲷

  // 四字节：U+10000（补充平面）只有 GB18030 编得出来
  final List<int> fourByte = gb18030.encode('\u{10000}');
  print(fourByte); // [144, 48, 129, 48]
  print(gb18030.decode(fourByte) == '\u{10000}'); // true

  // 按名字取，认别名；不认识返回 null
  print(chineseEncodingByName('cp936')); // gbk（GbkCodec 实例）
  print(chineseEncodingByName('big5-hkscs')); // big5-hkscs
  print(chineseEncodingByName('shift_jis')); // null

  // 同一个字节对在两套繁体编码里是不同的字：CP950 是「ヾ」、HKSCS 是「①」。
  // 用错了不会报错，只是个别字不对 —— 所以要按来源选编码，不是「谁大用谁」。
  print(big5.decode(<int>[0xc6, 0xa1])); // ヾ
  print(big5hkscs.decode(<int>[0xc6, 0xa1])); // ①

  // ---- 2. 这段字节是什么编码 ----
  print('\n[2] 不知道编码时：');
  final String text = readLegacyBytes(simplified);
  print('  读出来：$text');

  print('  只剩一个候选的例子（GB18030 四字节）：');
  print('  ${codecsThatRoundTrip(fourByte).map((Encoding e) => e.name)}');

  // 回环校验只证明「字节合法且自洽」，不判断语义：
  // 同一段简体字节按 Big5 解出来是「笢恅」，回环同样通过。
  print('  简体字节按 Big5：${big5.decode(simplified)}，'
      '回环 ${verifyRoundTrip(simplified, big5)}');

  // ---- 3. 坏字节的三种处理 ----
  print('\n[3] 遇到坏字节：');

  final List<int> broken = <int>[0x61, 0xff, 0x62, 0xa4];

  // 默认严格：抛 FormatException，offset 是坏字节在输入里的位置
  try {
    gbk.decode(broken);
  } on FormatException catch (e) {
    print('  严格模式：${e.message} @ ${e.offset}'); // Invalid gbk byte sequence @ 1
  }

  // 只想「尽量读出来」：坏字节换成 U+FFFD，与 utf8 的 allowMalformed 同义
  print('  宽松模式：${const GbkCodec(allowInvalid: true).decode(broken)}'); // a�b�

  // 还想知道坏在哪：decodeLossy 给出每个被替换字节的偏移
  final DecodeReport report = GbkCodec().decodeLossy(broken);
  print('  文本：${report.text}'); // a�b�
  print('  丢了 ${report.lostBytes} 个字节，位置 ${report.lostOffsets}'); // [1, 3]
  print('  干净吗：${report.isClean}'); // false

  // ---- 4. 导出前检查 ----
  print('\n[4] 能不能存成目标编码：');
  checkExportable('中文 abc', gb2312);
  checkExportable('中文 𣲷 \u{20000}', gb2312);

  // ---- 5. 流式解码 ----
  // 文件大、不想整段进内存时用这个。故意按 3 个字节切块，让汉字的两字节、
  // 甚至 GB18030 四字节序列被切在相邻两块里。
  print('\n[5] 分块解码（按 3 字节切，故意切开多字节字符）：');
  // 用 CJK 扩展 B 的 𠀀（U+20000）当四字节样例：它看着还是汉字，
  // 换成 U+10000 会打出线形文字 B 的 𐀀，容易被误读成乱码。
  final List<int> whole = gb18030.encode('中文 𣲷 \u{20000} 排版测试');
  final List<List<int>> chunks = <List<int>>[
    for (int i = 0; i < whole.length; i += 3)
      whole.sublist(i, i + 3 > whole.length ? whole.length : i + 3),
  ];
  final String streamed = await gb18030.decodeStream(
    Stream<List<int>>.fromIterable(chunks),
  );
  print('  ${chunks.length} 块拼回来：$streamed');
  print('  与整段解码一致：${streamed == gb18030.decode(whole)}');
  // 文件场景直接接在 openRead() 上，不必先 readAsBytes：
  //   final String text = await gbk.decodeStream(file.openRead());
  // 也可以用 transform（同样走这条增量路径）：
  //   final String text = await file.openRead().transform(gbk.decoder).join();

  // ---- 6. 增量是真增量：不用等流结束 ----
  print('\n[6] 边收边出：');
  final StreamController<List<int>> input = StreamController<List<int>>();
  final List<String> picked = <String>[];
  final StreamSubscription<String> subscription =
      input.stream.transform(gbk.decoder).listen(picked.add);

  input.add(gbk.encode('中文'));
  await Future<void>.delayed(Duration.zero);
  print('  流还没关，已经读到：${picked.join()}');

  input.add(gbk.encode('ABC'));
  await Future<void>.delayed(Duration.zero);
  print('  再来一块：${picked.join()}');

  await input.close();
  await subscription.cancel();
  print('  共收到 ${picked.length} 段、拼起来 ${picked.join().length} 个字符');

  // ---- 7. 写回老文件：编码方向 ----
  print('\n[7] 编码方向（写回文件）：');

  // 编不出来的字符总是抛 FormatException —— allowInvalid 只管解码，不会凭空造字
  try {
    gbk.encode('中文 𣲷');
  } on FormatException catch (e) {
    print('  严格编码：${e.message}'); // U+23CB7 is not representable in gbk
  }

  // 真正落盘：readAsString / writeAsString 直接吃 Encoding，不必自己转字节
  final Directory dir = Directory.systemTemp.createTempSync('chinese_codec_');
  try {
    final File legacy = File('${dir.path}/legacy.txt');
    legacy.writeAsStringSync('中文 abc', encoding: gbk);
    print('  写出的字节：${legacy.readAsBytesSync()}');
    print('  再读回来：${legacy.readAsStringSync(encoding: gbk)}');
  } finally {
    dir.deleteSync(recursive: true);
  }

  // 编码方向同样能分块：字符被切成两块时，半个代理对会留到下一块再一起编
  const String supplementary = '\u{20000}'; // 代理对，GB18030 编成四字节
  final List<int> straight = gb18030.encode('A$supplementary B');
  final List<List<int>> parts = await Stream<String>.fromIterable(<String>[
    'A${supplementary.substring(0, 1)}', // 结尾是高位代理
    '${supplementary.substring(1)} B', // 开头是低位代理
  ]).transform(gb18030.encoder).toList();
  final List<int> pieced = parts.expand((List<int> part) => part).toList();
  print('  切开代理对再拼：${pieced.join(',')}');
  print('  与整段编码一致：${pieced.join(',') == straight.join(',')}');
}
