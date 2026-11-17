# 变更记录

[English](https://github.com/bigedev/chinese_codec/blob/main/CHANGELOG.md) | **简体中文**

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
