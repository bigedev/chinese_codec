import 'dart:async';
import 'dart:math';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

/// 每种编码自己编得出来的语料：ASCII + 双字节 +（能编的话）四字节 / 代理对 / 组合字符。
const Map<String, String> _corpora = <String, String>{
  'gb18030': '中文ABC\u{10000}\u{20000}，。24',
  'gbk': '中文ABC，。！24',
  'gb2312': '中文ABC，。！24',
  'big5': '中文ABC，。！24',
  // 0x8862 是「一个字节对换两个码位」的组合字符，𣲷 在补充平面（解码要出代理对）
  'big5-hkscs': '中文ABC，。！\u00CA\u0304\u{23CB7}24',
};

Encoding _codec(String name) => chineseEncodingByName(name)!;

Encoding _lenientOf(Encoding codec) => switch (codec.name) {
      'gb18030' => const Gb18030Codec(allowInvalid: true),
      'gbk' => const GbkCodec(allowInvalid: true),
      'gb2312' => const Gb2312Codec(allowInvalid: true),
      'big5' => const Big5Codec(allowInvalid: true),
      _ => const Big5HkscsCodec(allowInvalid: true),
    };

/// 严格 + 宽松共 10 个实例。
Iterable<Encoding> _instances() sync* {
  for (final Encoding codec in chineseCodecs) {
    yield codec;
    yield _lenientOf(codec);
  }
}

/// 整段解码的结果，异常折成字符串（连同偏移一起比）。
String _whole(Encoding codec, List<int> bytes) {
  try {
    return 'ok:${codec.decode(bytes)}';
  } on FormatException catch (e) {
    return 'err@${e.offset}';
  }
}

/// 分块解码的结果，形态与 [_whole] 一致。
Future<String> _chunked(Encoding codec, List<List<int>> chunks) async {
  try {
    return 'ok:${await codec.decodeStream(Stream<List<int>>.fromIterable(chunks))}';
  } on FormatException catch (e) {
    return 'err@${e.offset}';
  }
}

/// 把 [bytes] 按 1..len 的随机块长切开（至少一块，空输入给一块空的）。
List<List<int>> _split(List<int> bytes, Random random) {
  if (bytes.isEmpty) return <List<int>>[<int>[]];
  final List<List<int>> chunks = <List<int>>[];
  int start = 0;
  while (start < bytes.length) {
    final int take = 1 + random.nextInt(bytes.length - start);
    chunks.add(bytes.sublist(start, start + take));
    start += take;
  }
  return chunks;
}

void main() {
  group('分块解码 == 整段解码', () {
    test('随机字节 × 随机切分', () async {
      // 固定种子：失败可复现。字节表故意混入 ASCII、首字节、次字节、数字与边角值，
      // 让「四字节形式的第二个字节是数字」「首字节后面跟非法尾字节」这些分支都被压到。
      final Random random = Random(20261117);
      const List<int> alphabet = <int>[
        0x00, 0x20, 0x41, 0x7e, 0x7f, 0x30, 0x39, //
        0x80, 0x81, 0x87, 0xa1, 0xa4, 0xc4, 0xc6, 0xd6, 0xf9, 0xfa, 0xfe, 0xff,
        0x40,
      ];
      final List<Encoding> instances = _instances().toList();
      for (int round = 0; round < 1500; round++) {
        final List<int> bytes = List<int>.generate(
          random.nextInt(16),
          (_) => alphabet[random.nextInt(alphabet.length)],
        );
        final List<List<int>> chunks = _split(bytes, random);
        for (final Encoding codec in instances) {
          expect(
            await _chunked(codec, chunks),
            _whole(codec, bytes),
            reason: '${codec.name} 字节=$bytes 切分=$chunks',
          );
        }
      }
    });

    test('把合法字节序列截断到任意长度（压 close 收尾的那些尾巴）', () async {
      final Random random = Random(7);
      for (final MapEntry<String, String> corpus in _corpora.entries) {
        final Encoding strict = _codec(corpus.key);
        final List<int> bytes = strict.encode(corpus.value);
        for (final Encoding codec in <Encoding>[strict, _lenientOf(strict)]) {
          for (int length = 0; length <= bytes.length; length++) {
            final List<int> truncated = bytes.sublist(0, length);
            expect(
              await _chunked(codec, _split(truncated, random)),
              _whole(codec, truncated),
              reason: '${codec.name} 截到 $length 字节',
            );
          }
        }
      }
    });

    test('长流（多块，含 8 KB 边界）', () async {
      final StringBuffer sb = StringBuffer();
      while (sb.length < 100000) {
        sb.write('中文混合ASCII ＡＢＣ 0123456789 汉字测试，。！');
      }
      final String text = sb.toString();
      for (final MapEntry<String, String> corpus in _corpora.entries) {
        final Encoding codec = _codec(corpus.key);
        final String payload = corpus.key == 'gb18030' ? text : corpus.value;
        final List<int> bytes = codec.encode(payload);
        final List<List<int>> chunks = <List<int>>[];
        for (int i = 0; i < bytes.length; i += 8192) {
          chunks.add(bytes.sublist(
              i, i + 8192 > bytes.length ? bytes.length : i + 8192));
        }
        expect(await _chunked(codec, chunks), 'ok:$payload');
      }
    });
  });

  group('分块编码 == 整段编码', () {
    test('代理对被切在任意位置（含组合字符）', () async {
      for (final MapEntry<String, String> corpus in _corpora.entries) {
        final Encoding codec = _codec(corpus.key);
        final List<int> expected = codec.encode(corpus.value);
        for (int cut = 1; cut < corpus.value.length; cut++) {
          final List<int> bytes = await codec.encoder
              .bind(Stream<String>.fromIterable(<String>[
                corpus.value.substring(0, cut),
                corpus.value.substring(cut),
              ]))
              .expand((List<int> chunk) => chunk)
              .toList();
          expect(
            bytes,
            expected,
            reason: '${codec.name} 在第 $cut 个 code unit 处切开',
          );
        }
      }
    });
  });
}
