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
