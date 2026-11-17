import 'dart:async';
import 'dart:io';

import 'package:chinese_codec/chinese_codec.dart';
import 'package:test/test.dart';

/// 什么也不做的下游，用来单独测 sink 的生命周期。
class _NullSink implements Sink<String> {
  @override
  void add(String data) {}

  @override
  void close() {}
}

/// 每种编码一份自己编得出来的语料（含 ASCII、双字节、GB18030 四字节）。
Map<String, String> corpora() => <String, String>{
      'gb18030': '中文ABC\u{10000}\u{20000}24',
      'gbk': '中文ABC，。！24',
      'gb2312': '中文ABC，。！24',
      'big5': '中文ABC，。！24',
      'big5-hkscs': '中文ABC，。！24',
    };

Encoding codecOf(String name) => chineseEncodingByName(name)!;

Future<String> decodeChunks(Encoding codec, List<List<int>> chunks) =>
    codec.decoder.bind(Stream<List<int>>.fromIterable(chunks)).join();

void main() {
  // 0.1.2 的实现是「把整个流收齐再解」，这个辅助函数用来证明现在不是了：
  // 第一块只喂了半行，流还没关，字就该出来。
  test('文本边收边吐，不等流结束', () async {
    final StreamController<List<int>> input = StreamController<List<int>>();
    final List<String> out = <String>[];
    final StreamSubscription<String> sub =
        input.stream.transform(gbk.decoder).listen(out.add);

    input.add(gbk.encode('中文'));
    await pumpEventQueue();
    expect(out.join(), '中文'); // 流还开着，文本已经出来了

    input.add(gbk.encode('ABC'));
    await pumpEventQueue();
    expect(out.join(), '中文ABC');

    await input.close();
    await pumpEventQueue();
    await sub.cancel();
  });

  // decodeStream 只给最终字符串，看不出「边到边出」；那条由上面用
  // transform + 未关闭的流来证明。这里只保证结果与整段解码一致。
  test('decodeStream 跨块结果与整段一致（含四字节）', () async {
    final StreamController<List<int>> input = StreamController<List<int>>();
    final Future<String> all = gb18030.decodeStream(input.stream);

    input.add(gb18030.encode('中文'));
    await pumpEventQueue();
    input.add(gb18030.encode('A\u{10000}'));
    await pumpEventQueue();
    await input.close();
    expect(await all, '中文A\u{10000}');
  });

  group('任意切分点与整段解码结果一致', () {
    for (final MapEntry<String, String> corpus in corpora().entries) {
      test('${corpus.key}：每个切点', () async {
        final Encoding codec = codecOf(corpus.key);
        final List<int> bytes = codec.encode(corpus.value);
        final String whole = codec.decode(bytes);
        for (int cut = 1; cut < bytes.length; cut++) {
          expect(
            await decodeChunks(
              codec,
              <List<int>>[bytes.sublist(0, cut), bytes.sublist(cut)],
            ),
            whole,
            reason: '在 $cut 处切开',
          );
        }
      });

      test('${corpus.key}：切点落在每一对的中间（一刀两刀三刀都试）', () async {
        // 每个字节自成一块：任何多字节字符都必然被切开
        final Encoding codec = codecOf(corpus.key);
        final List<int> bytes = codec.encode(corpus.value);
        final String whole = codec.decode(bytes);
        expect(
          await decodeChunks(
            codec,
            bytes.map((int byte) => <int>[byte]).toList(),
          ),
          whole,
        );
        // 空块夹在中间不影响
        expect(
          await decodeChunks(
            codec,
            <List<int>>[
              <int>[],
              bytes.sublist(0, 3),
              <int>[],
              bytes.sublist(3),
              <int>[],
            ],
          ),
          whole,
        );
      });
    }
  });

  test('GB18030 四字节序列的每种切法', () async {
    for (final String rare in <String>[
      '\u{10000}',
      '\u{20000}',
      '\u{10FFFF}'
    ]) {
      final List<int> four = gb18030.encode(rare);
      expect(four.length, 4, reason: rare);
      for (int cut = 1; cut < four.length; cut++) {
        expect(
          await decodeChunks(
            gb18030,
            <List<int>>[four.sublist(0, cut), four.sublist(cut)],
          ),
          rare,
          reason: '$rare 在 $cut 处切开',
        );
      }
      // 一个字节一块
      expect(
        await decodeChunks(
          gb18030,
          four.map((int byte) => <int>[byte]).toList(),
        ),
        rare,
      );
    }
  });

  test('坏字节跨块：宽松模式按字节补 U+FFFD', () async {
    // 0x81 是首字节，跟着的 0x20 不是第二字节 ⇒ 这个字节坏了
    expect(
      await decodeChunks(
        const GbkCodec(allowInvalid: true),
        <List<int>>[
          <int>[0x81],
          <int>[0x20],
        ],
      ),
      '\uFFFD ',
    );
    // Big5 里 0x81 根本不是首字节，单独一块也能立刻判死
    expect(
      await decodeChunks(
        const Big5Codec(allowInvalid: true),
        <List<int>>[
          <int>[0x81],
          <int>[0x41],
        ],
      ),
      '\uFFFDA',
    );
  });

  group('严格模式', () {
    test('流结束时孤立的首字节抛 FormatException', () async {
      await expectLater(
        gbk.decodeStream(Stream<List<int>>.fromIterable(<List<int>>[
          <int>[0x41],
          <int>[0x81],
        ])),
        throwsFormatException,
      );
      await expectLater(
        gb18030.decodeStream(Stream<List<int>>.value(<int>[0x81, 0x30, 0x81])),
        throwsFormatException,
      );
    });

    test('流结束时凑不齐的四字节序列按坏字节收尾（宽松模式）', () async {
      // [0x81,0x30] 只凑了四字节形式的前两个字节
      expect(
        await decodeChunks(
          const Gb18030Codec(allowInvalid: true),
          <List<int>>[
            <int>[0x41, 0x81],
            <int>[0x30],
          ],
        ),
        const Gb18030Codec(allowInvalid: true).decode(<int>[0x41, 0x81, 0x30]),
      );
      expect(
        await decodeChunks(
          const Gb18030Codec(allowInvalid: true),
          <List<int>>[
            <int>[0x81],
            <int>[0x30],
          ],
        ),
        '\uFFFD0',
      );
    });

    test('报的偏移是整个流里的绝对位置', () async {
      // 三块共 4 个字节，坏字节是第三块那个 0x80（流里第 4 个字节，偏移 3）
      final List<List<int>> chunks = <List<int>>[
        <int>[0x41, 0x42],
        <int>[0x43],
        <int>[0x80],
      ];
      await expectLater(
        decodeChunks(gbk, chunks),
        throwsA(
          isA<FormatException>()
              .having((FormatException e) => e.offset, 'offset', 3),
        ),
      );
    });

    test('报错之后不再消费后续分块（否则拿过期的尾巴拼出多余字符）', () async {
      // 0x81 在块尾被留着等下一块，下一块来的 0x20 不是第二字节 ⇒ 报错。
      // 报错后 0x81 仍停在 pending 里，若继续解，会和第三块的 0x43 拼成「丆」。
      final List<String> out = <String>[];
      final List<int?> errors = <int?>[];
      final StreamSubscription<String> sub = gbk.decoder
          .bind(Stream<List<int>>.fromIterable(<List<int>>[
        <int>[0x41, 0x81],
        <int>[0x20, 0x42],
        <int>[0x43],
      ]))
          .listen(out.add, onError: (Object e) {
        errors.add(e is FormatException ? e.offset : null);
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(out.join(), 'A');
      expect(errors, <int?>[1]);
    });

    test('同一块里坏字节之前的文本照样交出', () async {
      // 与 utf8 解码器一致：报错的是 0x81，它前面的 AB 已经在同一块里解出来了
      final List<String> out = <String>[];
      Object? error;
      final StreamSubscription<String> sub = gbk.decoder
          .bind(Stream<List<int>>.value(<int>[0x41, 0x42, 0x81, 0x20]))
          .listen(out.add, onError: (Object e) {
        error = e;
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(out.join(), 'AB');
      expect(
        error,
        isA<FormatException>()
            .having((FormatException e) => e.offset, 'offset', 2),
      );
    });

    test('中途报错时已经吐出的前缀仍然完整', () async {
      final List<String> out = <String>[];
      Object? error;
      final StreamSubscription<String> sub = gbk.decoder
          .bind(Stream<List<int>>.fromIterable(<List<int>>[
        <int>[0x41, 0x42],
        <int>[0x80],
      ]))
          .listen(out.add, onError: (Object e) {
        error = e;
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(out.join(), 'AB');
      expect(error, isA<FormatException>());
    });
  });

  group('Sink 生命周期', () {
    test('close 之后再 add 抛 StateError，重复 close 是幂等的', () async {
      final StreamController<List<int>> input = StreamController<List<int>>();
      final Future<String> all = gbk.decodeStream(input.stream);
      await input.close();
      expect(await all, '');
      // transformer 内部的 sink 已经关了：再喂一块应该报错而不是悄悄吞掉
      expect(
          () =>
              gbk.decoder.startChunkedConversion(_NullSink()).add(<int>[0x41]),
          returnsNormally);
      final Sink<List<int>> sink =
          gbk.decoder.startChunkedConversion(_NullSink());
      sink
        ..add(<int>[0x41])
        ..close();
      expect(() => sink.add(<int>[0x42]), throwsStateError);
      expect(sink.close, returnsNormally);
    });
  });

  group('编码方向', () {
    test('代理对被切在两块里也能编（块间只看得到半个字符）', () async {
      const String text = '\u{20000}A';
      final String high = String.fromCharCode(text.codeUnitAt(0));
      final String low = String.fromCharCode(text.codeUnitAt(1));
      final List<int> bytes = await gb18030.encoder
          .bind(Stream<String>.fromIterable(<String>[high, low, 'A']))
          .expand((List<int> chunk) => chunk)
          .toList();
      expect(bytes, gb18030.encode(text));
    });

    test('流结束时只剩半个代理：与整段编码一样抛', () async {
      const String high = '\uD840';
      await expectLater(
        gb18030.encoder.bind(Stream<String>.value(high)).join(),
        throwsFormatException,
      );
    });

    test('组合字符（一格两码位）被切开也能编', () async {
      // 0x8862 是 U+00CA U+0304 一格两字符：切在两个码位之间时不能只编前一半
      const String combining = '\u00CA\u0304';
      final List<int> expected = big5hkscs.encode(combining);
      expect(expected, <int>[0x88, 0x62]);
      final List<int> bytes = await big5hkscs.encoder
          .bind(Stream<String>.fromIterable(<String>[
            '\u00CA',
            '\u0304A',
          ]))
          .expand((List<int> chunk) => chunk)
          .toList();
      expect(bytes, <int>[...expected, 0x41]);
    });

    test('一块编不出来之后不再处理后续分块', () async {
      final List<int> out = <int>[];
      Object? error;
      final StreamSubscription<List<int>> sub = gbk.encoder
          .bind(Stream<String>.fromIterable(<String>['中文', '\u{10000}', 'ABC']))
          .listen(out.addAll, onError: (Object e) {
        error = e;
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(error, isA<FormatException>());
      // 只有第一块编出来了；后面两块不再处理（出错后上游不会自动停）
      expect(out, gbk.encode('中文'));
    });
  });

  group('真实文件（dart:io 走的就是这两条路径）', () {
    test('readAsString / readAsStringSync / decodeStream / transform 结果一致',
        () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('chinese_codec');
      addTearDown(() => dir.delete(recursive: true));

      const String line = '中文混合ABC 0123456789，。！';
      final StringBuffer sb = StringBuffer();
      while (sb.length < 200000) {
        sb.write(line);
      }
      final String expected = sb.toString();
      final File file = File('${dir.path}/legacy.txt');
      await file.writeAsBytes(gbk.encode(expected));

      expect(await file.readAsString(encoding: gbk), expected);
      expect(file.readAsStringSync(encoding: gbk), expected);
      expect(await gbk.decodeStream(file.openRead()), expected);
      expect(await file.openRead().transform(gbk.decoder).join(), expected);
    });
  });
}
