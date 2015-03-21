library chrome_native_messaging.example;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:unittest/unittest.dart';


class SingleResultSink implements Sink {
  bool _isClosed = false;
  var _result;

  get result {
    if (!_isClosed) throw new StateError();
    return _result;
  }

  void add(object) {
    if (_isClosed) throw new StateError();
    _result = object;
  }

  void close() { _isClosed = true; }
}

foo() {
  var bytes = UTF8.encode('[42, "fdsfdsfds"]');
  var codec = JSON.fuse(UTF8);
  var out = new SingleResultSink();
  ByteConversionSink sink = codec.decoder.startChunkedConversion(out);

  sink.add(bytes.sublist(0, 2));
  sink.add(bytes.sublist(2, 4));
  sink.add(bytes.sublist(4));
  sink.close();

  print(out.result);
}

main() async {

  test('single', testSingle);
  test('multiple', testMultiple);
  test('single split', testSingleSplit);
  test('multiple split', testMultipleSplit);
  test('multiple split 2', testMultipleSplit2);

  //test empty message.
}

enum DecoderState {
  ready,
  header,
  body
}

class MsgChunk {
  MsgChunk(this.size, this.data, {this.follows: false});
  // The size reported in the header.
  final int size;
  // True if this message is not the start of the message, but a fragment of an earlier message.
  final bool follows;
  final List<int> data;
  toString() => '(msg-chunk $size $follows $data)';
}

// Decodes a binary stream of json messages where the format is a 4 byte number header followed by the json encoded
// as UTF8. This data format is used for chrome's native messaging protocol.
Stream<Object> decodeJsonStream(Stream<List<int>> stream) => new JsonStreamDecoder(stream).decode();

class JsonStreamDecoder {

  Stream<List<int>> _input;

  JsonStreamDecoder(this._input);

  Stream<Object> decode() async* {
    final codec = JSON.fuse(UTF8);
    ByteConversionSink sink = null;
    SingleResultSink out = null;
    int bytesRead = 0;

    await for (MsgChunk chunk in _decodeChunks()) {
      if (chunk.size == chunk.data.length) {
        // Entire message is in a single chunk. This is the common case, so make it a special case.
        yield codec.decode(chunk.data);

      } else if (sink == null) {
        // Handle the first chunk of a message which is split across multiple chunks.
        bytesRead = chunk.data.length;
        out = new SingleResultSink();
        sink = codec.decoder.startChunkedConversion(out);
        sink.add(chunk.data);

      } else {
        // Handle a subsequent chunk of a message which is split across multiple chunks.
        bytesRead += chunk.data.length;
        assert(bytesRead <= chunk.size);
        sink.add(chunk.data);

        if (bytesRead == chunk.size) {
          // Done reading the message chunks.
          sink.close();
          sink = null;
          yield out.result;
          out = null;
          bytesRead = 0;
        }
      }
    }
  }

  Stream<MsgChunk> _decodeChunks() async* {
    List<int> header;
    int size = 0;
    int bytesRead = 0;
    DecoderState state = DecoderState.ready;

    await for (List<int> chunk in _input) {
      int i = 0;
      while (i < chunk.length) {
        int bytesRemaining = chunk.length - i;
        switch (state) {

          case DecoderState.ready:
            if (bytesRemaining >= 4) {
              size = _parseInt32(chunk, i);
              bytesRead = 0;
              i += 4;
              state = DecoderState.body;
            } else {
              header = chunk.sublist(i);
              i += header.length;
              state = DecoderState.header;
            }
            break;

          case DecoderState.header:
            assert(header.length > 0 && header.length < 4);
            int len = min(4 - header.length, bytesRemaining);
            header.addAll(chunk.sublist(i, len));
            i += len;
            assert(header.length <= 4);

            if (header.length == 4) {
              size = _parseInt32(header, 0);
              bytesRead = 0;
              state = DecoderState.body;
            }
            break;

          case DecoderState.body:
            int len = min(size - bytesRead, bytesRemaining);
            var data = chunk.sublist(i, i + len);
            yield new MsgChunk(size, data, follows: bytesRead > 0);
            bytesRead += len;
            i += len;
            state = size == bytesRead ? DecoderState.ready : DecoderState.body;
            break;
        }
      }
    }
  }

  //TODO handle the host computer's endianess.
  int _parseInt32(List<int> data, int offset) {
    int i = offset;
    List<int> d = data;
    int size = d[i] + (d[i + 1] << 8) + (d[i + 2] << 16) + (d[i + 3] << 24);
    return size;
  }

}



class JsonStreamDecoder2 {

  JsonStreamDecoder2(this._input);

  Stream<List<int>> _input;
  int _msgSize = 0; // The length of the message body in bytes, or 0.
  int _bytesRead = 0; // Number of bytes from the message body already processed.
  ByteConversionSink _sink = null;
  StringSink2 _out = null;

  Stream<Object> decode() async* {

    // Wait for chunks of bytes to arrive on the input stream.
    // The chunks do not neccessarily correspond with the message boundaries.
    await for (var chunk in _input) {

      // Not waiting for further chunks to complete a message, so start
      // parsing the message header.
      if (_sink == null) {
        for (var m in _readMessages(chunk)) yield m;
        continue;
      }

      // Handle a chunk from a message which has been split into multiple chunks.
      if (_msgSize > _bytesRead + chunk.length) {
        _sink.add(chunk);
        _bytesRead += chunk.length;
      } else {
        _sink.addSlice(chunk, 0, _msgSize - _bytesRead, true);
        _sink.close();
        _sink = null;
        _bytesRead = 0;
        yield JSON.decode(_out.toString());
      }
    }
  }

  // Return whole messages contained inside of a chunk.
  // If a partial message is encountered then start decoding it and
  // store the byte conversion sink in _sink.
  Iterable<Object> _readMessages(List<int> chunk) sync* {

    // Read all of the messages fully contained in the chunk.
    int i = 0;
    while (i + 4 <= chunk.length) {

      // Read header
      // TODO this depends on endianess of the cpu.
      _msgSize = chunk[i] +
      (chunk[i + 1] << 8) +
      (chunk[i + 2] << 16) +
      (chunk[i + 3] << 24);
      i += 4;

      //TODO if msgSize is too big then throw.
      // Check docs for maximum allowable message size.

      // Check if entire message body is contained in the chunk.
      // Length of the message body will be stored in _msgSize.
      if (i + _msgSize > chunk.length) break;

      var s = UTF8.decoder.convert(chunk, i, i + _msgSize);
      yield JSON.decode(s);

      i += _msgSize;
      _msgSize = 0;
    }

    if (_msgSize == 0 && chunk.length == i) return;

    // TODO Handle case where can't read header, need to store and wait for more data.
    if (_msgSize == 0 && chunk.length - i < 4) {
      throw new Exception('Could not read header - chunk size: ${chunk.length} bytes.');
    }

    // Only part of this message is stored in the current chunk, start the chunked
    // conversion and wait for more chunks to arrive asynchronously.
    _out = new StringSink2();
    _sink = UTF8.decoder.startChunkedConversion(_out);
    _sink.addSlice(chunk, i, chunk.length, false);
    _bytesRead = chunk.length - i;

  }

  // Return whole messages contained inside of a chunk.
  // If a partial message is encountered then start decoding it and
  // store the byte conversion sink in _sink.
  Iterable<Object> _readMessages2(List<int> chunk) sync* {

    int offset = 0;
    while (offset < chunk.length) {

      // TODO Handle case where can't read header, need to store and wait for more data.
      if (chunk.length < 4) throw new Exception('Could not read header - chunk size: ${chunk.length} bytes.');

      // Read header
      // TODO this depends on endianess of the cpu.
      _msgSize = chunk[offset] +
      (chunk[offset + 1] << 8) +
      (chunk[offset + 2] << 16) +
      (chunk[offset + 3] << 24);

      //TODO if msgSize is too big then throw.
      // Check docs for maximum allowable message size.

      offset += 4;

      if (_msgSize + 4 <= chunk.length) {
        var s = UTF8.decoder.convert(chunk, offset, offset + _msgSize);
        offset += _msgSize;
        yield JSON.decode(s);
      } else {
        // Only part of this message is stored in the current chunk, start the chunked
        // conversion and wait for more chunks to arrive asynchronously.
        _out = new StringSink2();
        _sink = UTF8.decoder.startChunkedConversion(_out);
        _sink.addSlice(chunk, offset, chunk.length, false);
        _bytesRead = chunk.length - offset;
        break;
      }
    }
  }
}


List<int> encodeMessage(Object msg) {
  var s = JSON.encode(msg);
  var bytes = UTF8.encode(s);
  int len = bytes.length;
  // This is actually supposed to depend on the endianess of the cpu.
  var out = <int> [
    len & 0xFF,
    (len >> 8) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 24) & 0xFF
  ];
  out.addAll(bytes);
  return out;
}

class StringSink2 implements Sink<String> {
  final StringBuffer _buffer = new StringBuffer();
  void add(String s) => _buffer.write(s);
  void close() {}
  String toString() => _buffer.toString();
}

testSingle() async {
  var msg = {"foo": "bar"};
  var bytes = encodeMessage(msg);
  var stream = new Stream.fromIterable([bytes]);
  var result = await decodeJsonStream(stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg])));
}

testMultiple() async {
  var msg1 = {"foo": "bar"};
  var msg2 = {"bob": 42};

  var bytes = new List<int>()
    ..addAll(encodeMessage(msg1))
    ..addAll(encodeMessage(msg2));

  var stream = new Stream.fromIterable([bytes]);
  var result = await decodeJsonStream(stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg1, msg2])));
}


testSingleSplit() async {
  var msg = {"foo": "bar"};
  var bytes = encodeMessage(msg);

  var ctl = new StreamController<List<int>>();
  ctl.add(bytes.take(6).toList());
  ctl.add(bytes.skip(6).toList());
  ctl.close();

  var result = await decodeJsonStream(ctl.stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg])));
}

testMultipleSplit() async {
  var msg1 = {"foo": "bar", "sdfdsfdsfdsf": "fdgdsfdsfsdfdsf", "sfdsfdsf": "fdgdsfdsfsdfdsf"};
  var msg2 = {"bob": 42, "fdsfdsf": [42, 43, 10000000, "dsfsdfsdfdsfdsf dsfdsfsdfsfs"]};

  var bytes = new List<int>()
    ..addAll(encodeMessage(msg1))
    ..addAll(encodeMessage(msg2));

  var ctl = new StreamController<List<int>>();

  // Split message into chunks.
  int i = 0;
  int chunkSize = 10;
  for (; i < bytes.length; i += chunkSize) {
    ctl.add(bytes.skip(i).take(chunkSize).toList());
  }
  if (i < bytes.length) ctl.add(bytes.skip(i).toList());
  ctl.close();

  var result = await decodeJsonStream(ctl.stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg1, msg2])));
}

testMultipleSplit2() async {
  var msg1 = [1, 2];
  var msg2 = [3, 4];

  var bytes = new List<int>()
    ..addAll(encodeMessage(msg1))
    ..addAll(encodeMessage(msg2));

  var ctl = new StreamController<List<int>>();

  // Split message into chunks.
  ctl.add(bytes.take(6).toList());
  ctl.add(bytes.skip(6).take(2).toList());
  ctl.add(bytes.skip(8).toList());
  ctl.close();

  var result = await decodeJsonStream(ctl.stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg1, msg2])));
}
//
//testMultipleSplit3() async {
//  var msg1 = ["abcd", "defg"];
//  var msg2 = ["abcd", "defg"];
//
//  var bytes = new List<int>()
//    ..addAll(encodeMessage(msg1))
//    ..addAll(encodeMessage(msg2));
//
//  var ctl = new StreamController<List<int>>();
//
//  // Split message into chunks.
//  ctl.add(bytes.take().toList());
//  ctl.add(bytes.skip(2).take(2).toList());
//  ctl.add(bytes.skip(4).toList());
//  ctl.close();
//
//  var result = await decodeJsonStream(ctl.stream).toList();
//
//  expect(JSON.encode(result), equals(JSON.encode([msg1, msg2])));
//}
