import 'package:chinese_codec/chinese_codec.dart';

/// 收集分块解码输出的下游。
///
/// 文件名没有 `_test` 后缀，所以 `dart test` 不会把它当成测试文件。
class CollectSink implements Sink<String> {
  final StringBuffer buffer = StringBuffer();

  @override
  void add(String data) => buffer.write(data);

  @override
  void close() {}
}

/// 整段解码的结果，异常折成字符串（连同偏移一起比）。
String wholeResult(Encoding codec, List<int> bytes) {
  try {
    return 'ok:${codec.decode(bytes)}';
  } on FormatException catch (e) {
    return 'err@${e.offset}';
  }
}

/// 分块解码的结果，形态与 [wholeResult] 一致。
///
/// 直接走 `startChunkedConversion`，不经过 Stream：逐格扫描要跑几十万次，不想每次都造
/// 一个 Stream 等事件循环。Stream 那一层的接线由 `stream_test.dart` 负责。
///
/// 注：报错时同一块里坏字节之前的文本不会出现在返回值里（这里只比错误偏移）。
String chunkedResult(Encoding codec, List<List<int>> chunks) {
  final CollectSink out = CollectSink();
  final Sink<List<int>> sink = codec.decoder.startChunkedConversion(out);
  try {
    for (final List<int> chunk in chunks) {
      sink.add(chunk);
    }
    sink.close();
  } on FormatException catch (e) {
    return 'err@${e.offset}';
  }
  return 'ok:${out.buffer}';
}

/// 把一个字节对切成两块喂进去。
String chunkedPair(Encoding codec, int lead, int trail) =>
    chunkedResult(codec, <List<int>>[
      <int>[lead],
      <int>[trail],
    ]);

String hexByte(int byte) => '0x${byte.toRadixString(16)}';
