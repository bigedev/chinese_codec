#!/usr/bin/env python3
"""生成 lib/src/tables.g.dart 与 lib/src/tables_big5hkscs.g.dart —— 中文字符集的映射表。

为什么要生成而不是手写：`dart:convert` 只有 UTF-8 / Latin-1 / ASCII，GBK 那套
是双字节码表（23,940 项），手抄一遍必然错几个字，还不容易发现。

数据来源：

- GB 系与 CP950：CPython 自带的 `gbk` / `gb18030` / `gb2312` / `cp950` 编解码器
  （映射源自 Unicode 官方的 CP936 / CP950 / GB18030 映射文件）。只取「码位 ↔ 字节」
  这个事实，不带任何 Python 代码。GB18030 的四字节区另按国标 2022 版附录 D 改过，
  见下面的 swaps_2022。
- Big5-HKSCS：WHATWG Encoding Standard 的 `index-big5.txt`（Big5 + HKSCS-2008 的
  web 实现基准），并用 CPython 的 `big5hkscs` 编解码器做第二来源交叉校验。这一份
  要联网抓（缓存在 tool/.cache/），带 SHA-256 校验；上游改了就人工核对差异再更新
  脚本里的常量，不要放开校验。

GB 系三张表压成两张位图 + 一张映射表的理由：GB2312 ⊂ GBK ⊂ GB18030 的**双字节区**，
实测三者映射没有冲突（GBK 不接受的位置在 GB18030 里落在 PUA），所以映射只需要
GB18030 那一份（最大集），GBK / GB2312 的差异用「这个位置该编码认不认」的位图表示。

Big5-HKSCS 单独一张表：它与 CP950 有 250 个格子映射不同（HKSCS 拿走了 ETen 的
假名与俄文/希腊字母区去放汉字），不能共用；而且有 1,713 个补充平面码位与 4 个
「一个格对两个码位」的组合字符，主表放不下，用 0xFFFF 当哨兵指向附加表。

用法（在包根目录）：

    python3 tool/gen_tables.py

跑完记得 `dart test` 复核往返一致性。
"""

import base64
import hashlib
import struct
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'lib' / 'src' / 'tables.g.dart'
HKSCS_OUT = ROOT / 'lib' / 'src' / 'tables_big5hkscs.g.dart'

LEADS = range(0x81, 0xFF)
TRAILS = [t for t in range(0x40, 0xFF) if t != 0x7F]
CELLS = [(lead, trail) for lead in LEADS for trail in TRAILS]
SURROGATE_LO, SURROGATE_HI = 0xD800, 0xDFFF

# Big5（CP950）：lead 0xA1-0xF9，trail 0x40-0x7E 与 0xA1-0xFE
BIG5_LEAD_MIN, BIG5_LEAD_MAX = 0xA1, 0xF9
BIG5_LEAD_COUNT = BIG5_LEAD_MAX - BIG5_LEAD_MIN + 1  # 89

# Big5 系（CP950 与 HKSCS 共用）的第二字节：0x40-0x7E 与 0xA1-0xFE
TRAILS_BIG5 = [t for t in range(0x40, 0xFF) if t <= 0x7E or t >= 0xA1]

# Big5-HKSCS：实际有字的首字节是 0x87-0xFE（0x81-0x86 规范预留未分配）
HKSCS_LEAD_MIN, HKSCS_LEAD_MAX = 0x87, 0xFE
# 主表里的哨兵：这一格的内容在附加表里（补充平面 或 组合字符）
HKSCS_EXTENDED = 0xFFFF

WHATWG_BIG5_URL = 'https://encoding.spec.whatwg.org/index-big5.txt'
# 2026-10 抓到的版本；上游改动过就人工核对差异，不要直接改这里的值
WHATWG_BIG5_SHA256 = \
    '08e24270c8e95d998c994c03f907e972480dc01f58743e078654cc466203c8ff'
WHATWG_CACHE = Path(__file__).resolve().parent / '.cache' / 'index-big5.txt'

# 「一个格对两个码位」的组合字符（HKSCS 把带声调的拉丁字母拆成基础字母 +
# 组合附加符）。WHATWG 的 index-big5.txt 里故意不给这四格，规范正文用一张
# 「Pointer / Code points」表单独定义，所以这里不能用下载的表推出来。
HKSCS_COMBINING = {
    (0x88, 0x62): '\u00ca\u0304',  # Ê̄  pointer 1133
    (0x88, 0x64): '\u00ca\u030c',  # Ê̌  pointer 1135
    (0x88, 0xa3): '\u00ea\u0304',  # ê̄  pointer 1164
    (0x88, 0xa5): '\u00ea\u030c',  # ê̌  pointer 1166
}


def seq_of_index(i: int) -> bytes:
    # 每一位的进位基数：b4 走 0-9（10）、b3 走 0x81-0xFE（126）、b2 走 0-9（10）、
    # b1 走 0x81-0xFE（126）。所以 (b1,b2) 一格是 126*10 = 1260，一个 b2off 档
    # 是 1260 而不是 126 —— 这里写错会让线性区整体偏移。
    b1off, rem = divmod(i, 10 * 1260)
    b2off, in_block = divmod(rem, 1260)
    b3off, b4off = divmod(in_block, 10)
    return bytes([0x81 + b1off, 0x30 + b2off, 0x81 + b3off, 0x30 + b4off])


def decode(codec: str, seq: bytes):
    try:
        return ord(seq.decode(codec))
    except (UnicodeDecodeError, TypeError):
        return None


def bitmask(flags) -> str:
    """按「序号 → 位」打包成位图，低位在前（与 Dart 端读法一致）。"""
    out = bytearray((len(flags) + 7) // 8)
    for i, on in enumerate(flags):
        if on:
            out[i >> 3] |= 1 << (i & 7)
    return base64.b64encode(bytes(out)).decode('ascii')


def big5_pointer_to_cell(pointer: int):
    """WHATWG 的 Big5 指针 → (首字节, 第二字节)。157 = 63 + 94 个 trail。"""
    lead = 0x81 + pointer // 157
    offset = pointer % 157
    trail = 0x40 + offset if offset < 63 else 0xA1 + offset - 63
    return (lead, trail)


def load_whatwg_big5():
    """抓 WHATWG 的 index-big5.txt，返回 {(lead, trail): 码位}。"""
    if not WHATWG_CACHE.exists():
        WHATWG_CACHE.parent.mkdir(parents=True, exist_ok=True)
        print('downloading %s ...' % WHATWG_BIG5_URL)
        urllib.request.urlretrieve(WHATWG_BIG5_URL, WHATWG_CACHE)
    raw = WHATWG_CACHE.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != WHATWG_BIG5_SHA256:
        raise SystemExit(
            'index-big5.txt 校验失败：%s\n期望 %s\n'
            '上游表改过就先人工核对差异，再更新 WHATWG_BIG5_SHA256。'
            % (digest, WHATWG_BIG5_SHA256))

    table = {}
    for line in raw.decode('utf-8').splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        pointer, code_point = line.split()[:2]
        table[big5_pointer_to_cell(int(pointer))] = int(code_point, 16)
    return table


def build_big5_hkscs():
    """Big5-HKSCS 的主表 + 附加表，并与 CPython 的 big5hkscs 交叉校验。"""
    mapping = load_whatwg_big5()

    table = []
    ext_cells = []   # 附加表里每一格的主表序号
    ext_texts = []   # 与 ext_cells 一一对应，每项恰好 2 个 UTF-16 单元
    for lead in range(HKSCS_LEAD_MIN, HKSCS_LEAD_MAX + 1):
        for trail in TRAILS_BIG5:
            cell = (lead, trail)
            index = len(table)
            text = HKSCS_COMBINING.get(cell)
            code_point = mapping.get(cell)
            if text is None and code_point is not None:
                text = chr(code_point) if code_point > 0xFFFF else None
            if text is not None:
                table.append(HKSCS_EXTENDED)
                ext_cells.append(index)
                ext_texts.append(text)
            else:
                table.append(code_point or 0)

    assert len(table) == (HKSCS_LEAD_MAX - HKSCS_LEAD_MIN + 1) * len(TRAILS_BIG5)
    # 附加表按「两个 UTF-16 单元」统一编码：补充平面是代理对，组合字符是两个 BMP 字符
    assert all(len(t.encode('utf-16-le')) == 4 for t in ext_texts)

    # 第二来源：CPython 的 big5hkscs（18,402 格）。相对下载的 index 表，它只多出那 4 个
    # 组合字符（规范把这几格挪出 index 表单独定义，见 HKSCS_COMBINING），其余 18,398 格
    # 全部落在本表里；反向则是本表多 192 格（HKSCS-2008 之后才补的字符）。
    #
    # 同格取值允许不同，但只出现在 Big5 经典的「一个字符两个格子」上（如 0xA145
    # 是「‧」还是「•」、0xA244 是「¥」还是「￥」），实测 11 格。这些格子 WHATWG
    # 与 CP950 一致，本包跟 WHATWG；CPython 取了另一些。超过上限就说明上游动过表。
    py_cells = 0
    conflicting = []
    for (lead, trail) in mapping:
        try:
            text = bytes([lead, trail]).decode('big5hkscs')
        except UnicodeDecodeError:
            continue
        py_cells += 1
        combining = HKSCS_COMBINING.get((lead, trail))
        if combining is not None:
            assert text == combining, (bytes([lead, trail]).hex(), repr(text))
            continue
        assert len(text) == 1, (bytes([lead, trail]).hex(), repr(text))
        if ord(text) != mapping[(lead, trail)]:
            conflicting.append((bytes([lead, trail]).hex(), hex(ord(text))))
    # 4 个组合格不在 mapping 里，所以总数要单独加上
    assert py_cells + len(HKSCS_COMBINING) == 18402, py_cells
    assert len(conflicting) == 11, conflicting

    return table, ext_cells, ext_texts


def main() -> None:
    # ---------- 双字节区：GB18030 是最大集 ----------
    table = []
    gbk_ok = []
    gb2312_ok = []
    gb2312_overrides = []  # (index, code_point)：GB2312 与 GB18030 少数位置不一致
    for index, (lead, trail) in enumerate(CELLS):
        seq = bytes([lead, trail])
        cp18030 = decode('gb18030', seq)
        cp_gbk = decode('gbk', seq)
        cp_2312 = decode('gb2312', seq)
        # GBK 是 GB18030 的真子集：有交集的地方必须一致
        assert cp_gbk in (None, cp18030), (seq.hex(), cp_gbk and hex(cp_gbk), cp18030 and hex(cp18030))
        table.append(cp18030 or 0)
        gbk_ok.append(cp_gbk is not None)
        gb2312_ok.append(cp_2312 is not None)
        # GB2312 有少数格子与 GBK/GB18030 映射到不同码位（A1A4 是「・」、A1AA 是「―」），
        # 差异用 override 表兜住，不为此再存一整张表
        if cp_2312 is not None and cp_2312 != cp18030:
            gb2312_overrides.append((index, cp_2312))
    assert len(table) == 23940, len(table)
    assert max(table) <= 0xFFFF
    assert len(gb2312_overrides) <= 8, gb2312_overrides

    # ---------- GB18030 四字节区 ----------
    # 先找出「补充平面线性区」的起点：U+10000 对应的那个序号
    linear_start = None
    for i in range(10 * 1260 * 10 * 126):
        cp = decode('gb18030', seq_of_index(i))
        if cp == 0x10000:
            linear_start = i
            break
    assert linear_start is not None

    # 抽查线性区：都是 cp = 0x10000 + (i - linear_start)
    for i in (linear_start, linear_start + 1, linear_start + 1000,
              linear_start + 0xFFFFF):
        cp = decode('gb18030', seq_of_index(i))
        assert cp == 0x10000 + (i - linear_start), (i, cp)

    # BMP 区先铺成「序号 → 码位」的字典（下面要按 2022 版改几个格子），最后再压成段
    bmp_map = {}
    for i in range(linear_start):
        cp = decode('gb18030', seq_of_index(i))
        if cp is None or SURROGATE_LO <= cp <= SURROGATE_HI:
            continue
        bmp_map[i] = cp

    # ---------- GB18030-2022 的映射互换 ----------
    # 依据国标 GB 18030—2022 附录 D 表 D.1（2005 版给 10 个竖排标点、8 个汉字构件
    # 临时用了 PUA 码位，2022 版把「双字节码位」与「四字节码位」对应的码位互换），
    # 外加 A8BC ⇄ 8135F437（U+1E3F 与 PUA U+E7C7 互换）。数值与 ICU 的
    # gb18030-2022.ucm 逐条核对过：
    #   https://github.com/unicode-org/icu/blob/main/icu4c/source/data/mappings/gb18030-2022.ucm
    #
    # 与 ICU 的一处**有意分歧**：ICU 把上面 18 个四字节序列标成 |3（忽略），也就是
    # 老文件里那几个四字节序列在 ICU 下会解不出来；这里按国标做完整互换，让它们仍能
    # 解成原来的 PUA 码位，往返也保得住。
    swaps_2022 = [
        # (双字节格子, 对应的四字节序列, 2022 版该格子上的码位)
        ('a6d9', '84318236', 0xfe10), ('a6da', '84318238', 0xfe12),
        ('a6db', '84318237', 0xfe11), ('a6dc', '84318239', 0xfe13),
        ('a6dd', '84318330', 0xfe14), ('a6de', '84318331', 0xfe15),
        ('a6df', '84318332', 0xfe16), ('a6ec', '84318333', 0xfe17),
        ('a6ed', '84318334', 0xfe18), ('a6f3', '84318335', 0xfe19),
        ('fe59', '82359037', 0x9fb4), ('fe61', '82359038', 0x9fb5),
        ('fe66', '82359039', 0x9fb6), ('fe67', '82359130', 0x9fb7),
        ('fe6d', '82359131', 0x9fb8), ('fe7e', '82359132', 0x9fb9),
        ('fe90', '82359133', 0x9fba), ('fea0', '82359134', 0x9fbb),
        ('a8bc', '8135f437', 0x1e3f),
    ]
    cell_index = {bytes([lead, trail]): i for i, (lead, trail) in enumerate(CELLS)}
    for cell_hex, four_hex, new_cp in swaps_2022:
        cell = bytes.fromhex(cell_hex)
        four = bytes.fromhex(four_hex)
        i = cell_index[cell]
        old_cp = table[i]
        assert old_cp not in (0, new_cp), (cell_hex, hex(old_cp))
        # 2005 版里这个四字节序列指向的正是 2022 版那个「真字符」
        four_index = (
            ((four[0] - 0x81) * 10 + (four[1] - 0x30)) * 1260
            + (four[2] - 0x81) * 10 + (four[3] - 0x30)
        )
        assert bmp_map.get(four_index) == new_cp, (four_hex, bmp_map.get(four_index))
        table[i] = new_cp
        bmp_map[four_index] = old_cp

    # 互换不该制造重复码位（编码时要能唯一反查）
    valid_cps = [cp for cp in table if cp]
    assert len(set(valid_cps)) == len(valid_cps)
    assert len(set(bmp_map.values())) == len(bmp_map)

    # BMP 区做成「连续段表」：GBK 覆盖不到的字符集中在这里，逐项存太占地方
    runs = []  # (index_start, code_point_start, length)
    for i in sorted(bmp_map):
        cp = bmp_map[i]
        if runs and cp == runs[-1][1] + runs[-1][2] and i == runs[-1][0] + runs[-1][2]:
            runs[-1] = (runs[-1][0], runs[-1][1], runs[-1][2] + 1)
        else:
            runs.append((i, cp, 1))

    # ---------- Big5（CP950）双字节表 ----------
    # 取 CP950 而不是「经典 Big5」：Windows 存盘的繁体文件基本都是 CP950，
    # 它是经典 Big5 的超集（多 42 个格子，另有 11 个格子映射到不同码位）。
    # HKSCS 走自己的表（tables_big5hkscs.g.dart）：它与 CP950 有 250 个格子
    # 映射不同，不能共用一张。
    big5 = []
    for lead in range(BIG5_LEAD_MIN, BIG5_LEAD_MAX + 1):
        for trail in TRAILS_BIG5:
            cp = decode('cp950', bytes([lead, trail]))
            assert cp is None or cp <= 0xFFFF, (lead, trail, cp)
            big5.append(cp or 0)
    assert len(big5) == BIG5_LEAD_COUNT * len(TRAILS_BIG5), len(big5)
    assert len(set(cp for cp in big5 if cp)) < len([cp for cp in big5 if cp]), 'CP950 应有重复码位'

    # ---------- 输出 ----------
    table_b64 = base64.b64encode(struct.pack('<%dH' % len(table), *table)).decode('ascii')
    chunks = [table_b64[i:i + 76] for i in range(0, len(table_b64), 76)]

    lines = []
    lines.append('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    lines.append('//')
    lines.append('// 由 tool/gen_tables.py 从 CPython 的 gbk / gb18030 / gb2312 编解码器生成。')
    lines.append('// 映射数据源自 Unicode 的 CP936 / GB18030 映射文件。')
    lines.append('')
    lines.append('/// 双字节区（GB18030 的最大集）：lead 0x81-0xFE × trail 0x40-0xFE（跳过 0x7F），')
    lines.append('/// 序号 `(lead - 0x81) * 190 + (trail < 0x7F ? trail - 0x40 : trail - 0x41)`。')
    lines.append('/// 值 0 表示该位置不是合法字符。GBK / GB2312 的差别由下面两张位图给出。')
    lines.append('const String doubleByteTableBase64 =')
    for idx, chunk in enumerate(chunks):
        tail = "';" if idx == len(chunks) - 1 else "'"
        lines.append("    '%s%s" % (chunk, tail))
    lines.append('')
    for name, flags, note in (
        ('gbkValidityBase64', gbk_ok, 'GBK 接受哪些双字节位置'),
        ('gb2312ValidityBase64', gb2312_ok, 'GB2312 接受哪些双字节位置（真子集）'),
    ):
        lines.append('/// %s：一位一个序号，低位在前。' % note)
        lines.append("const String %s =" % name)
        b64 = bitmask(flags)
        pieces = [b64[i:i + 76] for i in range(0, len(b64), 76)]
        for idx, chunk in enumerate(pieces):
            tail = "';" if idx == len(pieces) - 1 else "'"
            lines.append("    '%s%s" % (chunk, tail))
        lines.append('')
    lines.append('/// GB2312 与 GB18030 双字节映射不一致的格子：每 2 个整数一组 ——')
    lines.append('/// 序号、该序号在 GB2312 里的码位（GB18030 的码位仍以主表为准）。')
    lines.append('const List<int> gb2312Overrides = <int>[')
    flat = [v for pair in gb2312_overrides for v in pair]
    lines.append('  %s,' % ', '.join(str(v) for v in flat))
    lines.append('];')
    lines.append('')
    big5_b64 = base64.b64encode(struct.pack('<%dH' % len(big5), *big5)).decode('ascii')
    lines.append('/// Big5（CP950）双字节表：lead 0xA1-0xF9（89 个）× trail（0x40-0x7E 与')
    lines.append('/// 0xA1-0xFE，共 157 个），序号')
    lines.append('/// `(lead - 0xA1) * 157 + (trail < 0x7F ? trail - 0x40 : trail - 0xA1 + 63)`。')
    lines.append('/// 值 0 表示该位置不是合法字符。HKSCS 不在这张表里，见 tables_big5hkscs.g.dart。')
    lines.append('const String big5TableBase64 =')
    pieces = [big5_b64[i:i + 76] for i in range(0, len(big5_b64), 76)]
    for idx, chunk in enumerate(pieces):
        tail = "';" if idx == len(pieces) - 1 else "'"
        lines.append("    '%s%s" % (chunk, tail))
    lines.append('')
    lines.append('/// 4 字节序列里「补充平面线性区」的起始序号（此序号对应 U+10000）。')
    lines.append('const int gb18030LinearStart = %d;' % linear_start)
    lines.append('')
    lines.append('/// BMP 内的 4 字节映射，按「连续段」压紧：')
    lines.append('/// 每 3 个整数是一段 —— 起始序号、起始码位、长度。')
    lines.append('const List<int> gb18030BmpRuns = <int>[')
    row = []
    for r in runs:
        row.extend(r)
        if len(row) >= 12:
            lines.append('  %s,' % ', '.join(str(v) for v in row))
            row = []
    if row:
        lines.append('  %s,' % ', '.join(str(v) for v in row))
    lines.append('];')
    lines.append('')

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(lines), encoding='utf-8')
    print('wrote %s' % OUT)
    print('  双字节 23940 项：GBK 认 %d、GB2312 认 %d'
          % (sum(gbk_ok), sum(gb2312_ok)))
    print('  GB18030 线性区起点 %d，BMP 段 %d 段' % (linear_start, len(runs)))
    print('  Big5(CP950) %d 格，有效 %d' % (len(big5), sum(1 for cp in big5 if cp)))
    print('  文件大小 %.1f KB' % (OUT.stat().st_size / 1024))

    # ---------- Big5-HKSCS 输出 ----------
    hkscs, ext_cells, ext_texts = build_big5_hkscs()
    hk = []
    hk.append('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    hk.append('//')
    hk.append('// 由 tool/gen_tables.py 从 WHATWG Encoding Standard 的 index-big5.txt 生成')
    hk.append('// （Big5 + HKSCS-2008），并与 CPython 的 big5hkscs 编解码器交叉校验。')
    hk.append('')
    hk.append('/// Big5-HKSCS 主表：lead 0x87-0xFE（120 个）× trail 0x40-0x7E 与 0xA1-0xFE')
    hk.append('/// （157 个），序号')
    hk.append('/// `(lead - 0x87) * 157 + (trail < 0x7F ? trail - 0x40 : trail - 0xA1 + 63)`。')
    hk.append('/// 值 0 表示不合法；0xFFFF 表示内容在下面的附加表里（补充平面或组合字符）。')
    hk.append('const String hkscsTableBase64 =')
    hk_b64 = base64.b64encode(
        struct.pack('<%dH' % len(hkscs), *hkscs)).decode('ascii')
    for chunk in _wrap(hk_b64):
        hk.append(chunk)
    hk.append('')
    hk.append('/// 附加表的格子序号（升序）：主表里 0xFFFF 的那 1,717 格。')
    hk.append('const String hkscsExtendedCellsBase64 =')
    cells_b64 = base64.b64encode(
        struct.pack('<%dH' % len(ext_cells), *ext_cells)).decode('ascii')
    for chunk in _wrap(cells_b64):
        hk.append(chunk)
    hk.append('')
    hk.append('/// 附加表的文本，UTF-16LE：每 2 个单元一项，与上一张表逐项对应。')
    hk.append('/// 补充平面字符是代理对（1 个 rune），组合字符是两个 BMP 字符（2 个 rune），')
    hk.append('/// 但都恰好占 2 个 UTF-16 单元，所以能用同一种定长编码。')
    hk.append('const String hkscsExtendedTextBase64 =')
    text_b64 = base64.b64encode(''.join(ext_texts).encode('utf-16-le')).decode('ascii')
    for chunk in _wrap(text_b64):
        hk.append(chunk)
    hk.append('')

    HKSCS_OUT.parent.mkdir(parents=True, exist_ok=True)
    HKSCS_OUT.write_text('\n'.join(hk), encoding='utf-8')
    print('wrote %s' % HKSCS_OUT)
    print('  Big5-HKSCS %d 格，有效 %d（其中附加表 %d：补充平面 %d、组合字符 %d）'
          % (len(hkscs), sum(1 for v in hkscs if v),
             len(ext_cells),
             sum(1 for t in ext_texts if len(t) == 1),
             sum(1 for t in ext_texts if len(t) == 2)))
    print('  文件大小 %.1f KB' % (HKSCS_OUT.stat().st_size / 1024))


def _wrap(text: str, width: int = 76):
    """把 base64 切成 Dart 字符串字面量（末段带分号）。"""
    return ["    '%s%s" % (text[i:i + width],
                           "';" if i + width >= len(text) else "'")
            for i in range(0, len(text), width)]


if __name__ == '__main__':
    main()
