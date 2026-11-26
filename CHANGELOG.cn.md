# 变更记录

[English](https://github.com/bigedev/chinese_codec/blob/main/CHANGELOG.md) | **简体中文**

## 0.1.4

只有文档与示例的变化 —— 接口、映射表、行为都没动，升级只为拿到新文档。

- **新增「安装」小节**：`dart pub add chinese_codec`，并说明 Flutter 工程除这条依赖外
  不需要别的配置。
- **修掉一段编译不过的示例**：「先试 UTF-8，再试中文编码」那段原来是顶层代码块里的
  裸 `return`，现在是完整的 `readLegacy(bytes)` 函数，可以直接抄。
- **「用法」拆成四个子节** —— 基本编解码 / 文件与流 / 读不干净的数据 / 按名字取，长页面
  可以按需跳读，不必整页滚。
- **覆盖表的计数改成「字符」而不是「格子」**：Big5 13,742、Big5-HKSCS 18,494 —— 因为
  Big5 有 10 个字节对重复映射同一字符，HKSCS 那 4 个组合字符是一个字节对出两个字符。
  GBK 21,791 / GB2312 7,445 / GB18030 23,940 不变。
- **删掉重复段落**（增量解码、不做探测、HKSCS 数据来源各讲了两遍），README 也不再写死
  版本号，以后升版本不用回头改文档。
- **交叉核对的口径改准了**：Big5 与 CPython 的 `cp950` 在全部 13,752 格上一致，而 macOS
  `iconv` 的 CP950 不认 ETen 扩展区那 249 格 —— 所以文档改成说明这 13,503 格的交集，
  不再笼统写「与 iconv 的 CP950 逐格一致」。
- **示例补上「出错那半边」**：严格模式的 `FormatException` 与其字节偏移、`allowInvalid`、
  CP950 与 HKSCS 同字节不同字（`0xC6A1` → ヾ / ①）、GBK 文件写入后读回、以及代理对被切
  成两块时的分块编码。

## 0.1.3

- **新增四个「这文件是什么编码」的辅助函数**——给的是证据，不是猜测：
  - `tryDecode(bytes, encoding)`：严格解码，解不出来返回 `null` 而不抛异常；
  - `verifyRoundTrip(bytes, encoding)`：解出来再编回去，字节逐位相同才算通过；
  - `codecsThatRoundTrip(bytes)`：列出全部通过校验的候选——**0 条**表示「既不是 UTF-8、
    也不是任何中文编码」，**1 条**就是答案，**多条**说明字节空间重叠。文档写明了它的
    边界：`中文` 的 GBK 字节按 Big5 也能通过回环（解成 `笢恅`），所以它区分不了简繁，
    本包仍然不做猜测；
  - `unrepresentableRunes(text, encoding)`：列出目标编码**装不下的全部字符**，而
    `encode` 只报第一个。
- **五种编码都加了 `decodeLossy`**：宽松解码，并说明坏在哪。返回 `DecodeReport`，
  含 `text`、`lostOffsets`（升序字节偏移）与 `lostBytes`；文本里每个 U+FFFD 都对应
  一条偏移。它不受 `allowInvalid` 影响——报告只在宽松解码时才有意义。
- **流式解码改成真增量**：`decodeStream(...)`、`decoder.bind(...)`、
  `stream.transform(codec.decoder)` 每收到一块就吐出已经能确定的字符，不再先读完整个流。
  块尾只有 1~3 个「还判断不了」的字节留到下一块（GB18030 四字节形式最多三个）。8 KB 分块
  实测 74 → 96 MB/s（AOT，1 MB 语料），长文件也不再整段进内存。严格模式下坏字节可能在
  中途抛出：报错前已经解出的文本（包括报错那一块里坏字节**之前**的部分）照样交出，报错
  之后这条流不再产出文本 —— 出错后上游不会自动取消，继续解会拿块尾那份过期的待拼字节
  拼出本不该存在的字符。
- **流式解码的异常偏移改成整个流里的绝对位置**。原先报的是当前输入内的偏移，而流式解码
  没有一段连续输入可指，`FormatException.source` 为空。
- **编码方向不再怕「一个字符占两个 code unit」被切块**：补充平面字符的代理对、以及
  Big5-HKSCS 那 4 个组合字符（`0x8862` → U+00CA U+0304，两码位一格）被
  `stream.transform(codec.encoder)` 分到两块时，以前会抛「编不出来」，现在留到下一块
  拼回去再编；流结束时仍然只剩前一半则照旧抛。
- `example/` 从几条单行示例扩成完整走查：未知字节 → 候选编码 → 丢失报告 → 导出检查。

## 0.1.2

- **Big5-HKSCS 编码改用标准 Big5 区格子**：字符在标准区有格时，0.1.1 会写成 HKSCS 扩展区
  那一格（如「兙」写成 `0x92AF`），CP950 / Windows 解不出来。现在优先 lead `0xA1`–`0xF9`
  的标准区（「兙」是 `0xA259`）。受影响 56 个码位，解码方向不变。
- **Big5 / Big5-HKSCS 编码改用规范格**：CP950 里占两格的 `十` / `卅` 现在写 `0xA451` /
  `0xA4CA`（Windows、iconv 的 CP950、CPython 都是这个），不再是 `0xA2CC` / `0xA2CE`。
  两格都能正常解码。
- **分块转换可用**：`codec.decoder.bind(...)`、`codec.encoder.bind(...)`、
  `stream.transform(codec.decoder)` 以前直接抛 `UnsupportedError`。解码方向仍是「收齐再
  解」（一个汉字可能被切在两个 chunk 之间），编码方向逐块转。
- **解码快 2–3 倍、GB18030 编码快 8 倍**：解码不再为每个字造一个单字符 `String`；
  GB18030 编码不再用 `BytesBuilder` 逐字节写；反查表从哈希表换成 `Uint16List`
  （GBK 冷启动 2.7 ms → 0.13 ms，每个编码最多 1.7 MB → 128 KB）。
- `chineseEncodingByName` 去掉首尾空白，并多认几个别名：`GB-2312`、`CP-936`、`CP-950`、
  `X-GBK`、`GB18030-2000`、`GB18030-2022`。
- 重新导出 `dart:convert` 的 `Encoding`，写 `List<Encoding>` 时不必再单独 import。
- 文档补充：Big5 有 11 格标点跟 Windows CP950 走、与 CPython 的 `big5` 不同；
  Big5-HKSCS 有 11 格跟 WHATWG 走、与 glibc / CPython 不同。

## 0.1.1

- 补齐 pub.dev 的 API 文档：五个编解码类的构造函数与 `name` / `layout` / `encoder` /
  `decoder` / `decodeStream` / `toString` 都写清了取值与行为，不再只有签名。
  同时点明 `allowInvalid` **只影响解码** —— 编码方向编不出来的字符一律抛
  `FormatException`。
- 修复 `decodeStream`：`Converter` 没有实现分块转换，`dart:convert` 的默认实现一调用
  就抛 `UnsupportedError`。现在先把字节流读完再解码，多字节字符被切在两个 chunk 之间
  也能正常解。

## 0.1.0

- 首个版本：GB18030（1 / 2 / 4 字节，含补充平面线性区）、GBK、GB2312、Big5（CP950）、
  Big5-HKSCS 的编解码。
- GB18030 按 **2022 版**实现：含国标附录 D 表 D.1 的 19 组码位互换（10 个竖排标点、
  8 个汉字构件、U+1E3F ⇄ PUA U+E7C7），与 ICU 的 `gb18030-2022.ucm` 逐条对齐。
- GB 三家共用一张 GB18030 双字节表，GBK / GB2312 的差异用有效性位图 + 2 个 override 表示。
- 新增 **Big5-HKSCS**：18,594 个格子，含 1,713 个补充平面码位（粤语用字、人名地名用字）。
  数据取自 WHATWG Encoding Standard 的 `index-big5.txt`（Big5 + HKSCS-2008），
  并用 CPython 的 `big5hkscs` 交叉核对。
  - 与 Big5（CP950）**不是包含关系**：格子是 CP950 的超集，但 250 格映射不同
    （HKSCS 占用了 ETen 扩展的假名、俄文、希腊字母区，如 `0xC6A1` 是「①」而非「ヾ」），
    要按文件来源选编码。
  - 4 个格子是「一个字节对换两个码位」的组合字符（`0x8862` → U+00CA U+0304），
    编解码都按两个码位整体处理，可往返。
- `allowInvalid` 与 `utf8.decode(allowMalformed:)` 同义：坏字节变 U+FFFD 而不抛异常。
- `chineseCodecs` / `chineseEncodingByName()` 便于按名字（含 CP936、EUC-CN、Big5-HKSCS
  等别名）取编码。
