# chinese_codec

[English](https://github.com/bigedev/chinese_codec/blob/main/README.md) | **简体中文**

中文字符集编解码的纯 Dart 实现：**GB18030**（含四字节与补充平面）、**GBK**、**GB2312**、
**Big5**（CP950）、**Big5-HKSCS**（香港增补字符集）。无原生依赖、无 FFI，服务端、CLI、
Flutter（含鸿蒙 / 安卓）通用。

## 为什么

`dart:convert` 只有 UTF-8 / Latin-1 / ASCII。碰到 GBK / Big5 存盘的老文件（VB、Delphi、
早期 Windows 上的源码与配置）只能得到 `FormatException`，或者被当成 Latin-1 读成一堆
乱码 —— 后者更糟，因为它「没报错」。

## 用法

```dart
import 'dart:convert';
import 'package:chinese_codec/chinese_codec.dart';

void main() {
  final List<int> bytes = <int>[0xd6, 0xd0, 0xce, 0xc4];

  print(gbk.decode(bytes));      // 中文（简体）
  print(gb2312.decode(bytes));   // 中文（子集，同样能解）
  print(gb18030.decode(bytes));  // 中文
  print(big5.decode(<int>[0xa4, 0xa4, 0xa4, 0xe5]));  // 中文（繁体）
  print(big5hkscs.decode(<int>[0x9d, 0xb7]));         // 𣲷（香港，CP950 读不出来）

  print(gbk.encode('中文'));      // [214, 208, 206, 196]
}
```

五种编码都是 `Encoding` 的子类，所以能直接当 `File.readAsString(encoding:)` /
`File.writeAsString(encoding:)` 的参数：

```dart
final String text = File('legacy.bas').readAsStringSync(encoding: gbk);
File('legacy.utf8.bas').writeAsStringSync(text);  // 写出 UTF-8
```

文件大、不想整段读进内存时用流式解码。它是**真增量**的：每读到一块就把已经能确定的字符
交出来，只有块尾那 1~3 个「还判断不了」的字节留到下一块（一个汉字的两字节、GB18030 的
四字节序列都可能被切在两块之间）：

```dart
final String text = await gbk.decodeStream(file.openRead());
// 同样增量的另一种写法，方便接在别的 Stream 上，或顺手 map / filter
final String same = await file.openRead().transform(gbk.decoder).join();
```

块边界不影响结果，也不占内存：解出来的文本与 `decode(整个文件)` 逐字符相同。严格模式下
坏字节可能在中途抛出，此时已经交出的文本是完整的前缀 —— 包括报错那一块里坏字节之前的
部分，永远停在字符边界上，不会出现半个字；报错之后这条流不再产出文本。
`FormatException.offset` 是整个流里的字节位置。要「尽量全读出来、再看坏在哪」用下面的
`decodeLossy`。

怀疑内容不干净、想「尽量读出来」时：

```dart
const GbkCodec lenient = GbkCodec(allowInvalid: true);
final String text = lenient.decode(bytes);  // 坏字节 → U+FFFD，与 utf8 allowMalformed 同义
```

既要读出来、又想知道**坏在哪**时用 `decodeLossy` —— 它宽松解码，并给出每个被替换
字节的偏移：

```dart
final DecodeReport report = GbkCodec().decodeLossy(bytes);
if (!report.isClean) {
  print('丢了 ${report.lostBytes} 个字节，位置 ${report.lostOffsets}');
  // 例如「丢了 2 个字节，位置 [1, 3]」——report.text 里每个 U+FFFD 都对应一条偏移
}
```

按名字取（认 `CP936`、`EUC-CN`、`CP950` 这类别名，常用于解析 MIME / git 配置）：

```dart
chineseEncodingByName('cp936');      // GbkCodec
chineseEncodingByName('euc-cn');     // Gb2312Codec
chineseEncodingByName('cp950');      // Big5Codec
chineseEncodingByName('big5-hkscs'); // Big5HkscsCodec
```

## 覆盖范围

| 编码 | 单字节 | 双字节 | 四字节 | 说明 |
|---|---|---|---|---|
| GB2312 | ASCII | ✓（7,445 个字符） | ✗ | 最老的国标，GBK 的真子集 |
| GBK（CP936） | ASCII | ✓（21,791 个格子） | ✗ | Windows 上最常见的简体 |
| GB18030 | ASCII | ✓（23,940 个格子，含 GBK 不收的用户自定义区） | ✓ | BMP 补齐 + U+10000..U+10FFFF |
| Big5（CP950） | ASCII | ✓（13,752 个格子） | ✗ | 繁体；Windows 上最常见 |
| Big5-HKSCS | ASCII | ✓（18,594 个格子，含 CP950 的全部 13,752 格） | ✗ | 繁体；香港增补字符集，含 1,713 个补充平面码位 |

判定建议：**先试 UTF-8，失败再用往返校验确认中文编码**。覆盖面大的编码「能解」不等于
「解对了」—— 一段随机字节也可能被成功解成生僻字（或者合法但完全错误的字）。

```dart
final String? utf8Text = tryDecode(bytes, utf8);
if (utf8Text != null) return utf8Text;

final List<Encoding> fits = codecsThatRoundTrip(bytes);
// 0 条：既不是 UTF-8，也不是任何中文编码（截断 / 二进制 / 别的字符集）
// 1 条：就是它（GB18030 的四字节序列落在这一类）
// 多条：字节空间重叠，由业务决定
```

`codecsThatRoundTrip` 给的是**证据，不是猜测**：它只报告哪些编码能解开这段字节、
且编回去还是同样的字节。它有意不做两件事：

- **不区分简繁**。`中文` 的 GBK 字节按 Big5 同样能通过回环（解出来是 `笢恅`），
  所以普通简体文本五种编码可能全部通过。真正能收窄候选的是：GB2312 装不下的字、
  GB18030 的四字节序列、以及「根本不是文本」。
- **不按字频打分**。那是启发式，猜错比报错更难查，选择权留给调用方。

写文件前想确认目标编码是否装得下，用 `unrepresentableRunes` —— `encode` 遇到第一个
装不下的字符就抛，这个函数会把**全部**装不下的字符列出来：

```dart
final List<int> missing = unrepresentableRunes(text, gb2312);
if (missing.isNotEmpty) {
  print('GB2312 装不下：${missing.map(String.fromCharCode).join()}');
}
```

## 已知限制

- **GB18030 按 2022 版实现**（国标附录 D 表 D.1 的 19 组互换）：10 个竖排标点
  （`A6D9` 起）、8 个汉字构件（`FE59` 起）、以及 `A8BC` 那组，双字节格子与四字节序列
  上的码位互换。所以同一段字节在本包与 CPython（2000 / 2005 版）下可能分别解成
  「真字符」和 PUA —— 这是标准换版的结果，不是 bug。
  - 与 **ICU** 的 `gb18030-2022.ucm` 有一处**有意分歧**：ICU 把那 18 个四字节序列
    标成忽略（老文件里解不出来），本包按国标做完整互换，仍解成原来的 PUA 码位、
    往返可逆。
  - 表 D.2（6 个构件）与表 D.3（9 个 CJK 兼容汉字）只涉及**字形与字符集成员**，
    不动「字节 ↔ 码位」映射（ICU 的 2022 数据同样保留 `FD9C` → U+F92C 等映射），
    所以本包不受影响。
- **Big5 实现的是 CP950**（Windows 繁体中文的实际上限），比经典 Big5 多 42 个格子
  （例如 `0xA3E1` 是「€」）、另有 11 个格子映射到不同码位。
- **Big5-HKSCS 与 CP950 不是包含关系**：格子是它的超集（CP950 的 13,752 格全都在），
  但 **250 格映射不同** —— HKSCS 把 ETen 扩展的假名、俄文、希腊字母区
  （`0xC6A1`-`0xC8FE` 等）拿去放汉字与带圈数字，例如 `0xC6A1` 在 CP950 是「ヾ」、
  在 HKSCS 是「①」。所以：读 Windows 存盘的繁体文件用 `big5`，读香港的 HKSCS
  文件（粤语用字、人名与地名用字）用 `big5hkscs`。用错了**不会报错**，只会个别字不对，
  这正是要按来源选编码、而不是「谁大用谁」的原因。
- Big5-HKSCS 有 4 个格子是「一个字节对换两个码位」的组合字符（`0x8862` → U+00CA + U+0304
  这类带声调拉丁字母）：解码会得到两个字符，编码时按这两个码位的组合整体匹配、仍编回
  同一格。所以按「字符数 == 字节数 / 2」统计在这种文本上不成立。
- Big5-HKSCS 的数据取自 WHATWG 的 `index-big5.txt`（Big5 + HKSCS-2008，18,590 格）
  加规范正文单独定义的 4 个组合字符，共 18,594 格。CPython 的 `big5hkscs` 有 18,402 格，
  **全部包含在本包内**；本包另有 192 格（`0xA3E1` 的「€」、`0x877B` 的 U+21D53 等
  HKSCS-2008 之后才补的字符）。
- GB2312 里有两个格子与 GBK / GB18030 映射到不同码位（历史遗留）：
  `0xA1A4` 是「・」(U+30FB)、`0xA1AA` 是「―」(U+2015)。所以 `U+00B7` 在 GB2312 下
  不可表示 —— 这是国标本身的不一致，不是本包的偏差。
- 不做编码**探测**，只给证据：`tryDecode` / `verifyRoundTrip` / `codecsThatRoundTrip`
  会告诉你哪些编码**能**解释这段字节，但不会排序、不会替你选。字节空间本来就是重叠的，
  普通简体文本按 Big5 也能通过 —— 猜错比报错更难查，选择权留给调用方（见上面的「覆盖范围」）。

## 实现与体积

映射表由 `tool/gen_tables.py` 生成，只取「码位 ↔ 字节」这个事实，不含任何第三方实现代码：

- GB 系与 Big5：从 CPython 的 `gbk` / `gb18030` / `gb2312` / `cp950` 编解码器读，
  四字节区另按 GB 18030—2022 附录 D 改过（见上面的限制说明）。
- Big5-HKSCS：从 WHATWG 的 `index-big5.txt` 读（Big5 + HKSCS-2008），联网抓、
  带 SHA-256 校验、缓存在 `tool/.cache/`；再用 CPython 的 `big5hkscs` 逐格交叉核对。

表结构：

- GB 系：一张 GB18030 双字节表（23,940 项）+ 两张有效性位图（GBK / GB2312 各认哪些
  格子）+ 2 个 override；四字节 BMP 区压成 221 段连续映射，补充平面用线性公式（无需表）。
- Big5：一张 13,973 格的表（有效 13,752 格）。
- Big5-HKSCS：一张 18,840 格的表（有效 18,594 格），BMP 部分直接查表；1,717 个
  「一格出两个 UTF-16 单元」的格子（1,713 个补充平面字符 + 4 个组合字符）在主表里
  用 0xFFFF 当哨兵、转到附加表。反查表都在首次编码时构建。

生成结果约 192 KB 源码（`tables.g.dart` 123 KB + `tables_big5hkscs.g.dart` 69 KB），
各表首次使用时 lazy 解码；只用其中一种编码也只付一次代价。

改了生成脚本后务必 `dart test`：单测对**全表**做了往返校验（GBK 21,791、GB2312 7,445、
GB18030 双字节 23,940 + BMP 四字节 39,420、Big5 13,752、Big5-HKSCS 18,594），
能抓住写错一位。

## 数据来源与许可

- 包本身：MIT（见 [LICENSE](LICENSE)）。
- 映射数据源自 Unicode 官方的 CP936 / CP950 映射表、GB 2312 标准，以及
  **GB 18030—2022 附录 D**（2022 版互换）与 ICU 的 `gb18030-2022.ucm` 核对结果，
  属于事实性数据；本项目以 MIT 分发，未包含任何第三方实现代码。
- Big5-HKSCS 的映射取自 **WHATWG Encoding Standard** 的 `index-big5.txt`
  （Big5 + HKSCS-2008，规范以 CC BY 4.0 发布）。同样只取「字节 ↔ 码位」这一层
  事实性数据，未包含规范正文或任何实现的代码。四个组合字符的取值来自规范正文的
  「Pointer / Code points」表。
- 保留 `A3A0` → U+E5E5（PUA）：ICU 的 2022 表里没有这一格，但 2005 及多数实现仍映射
  它，删掉只会让老文件解不出来，代价不对称。
