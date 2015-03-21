library chrome_native_messaging.json_stream;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

// Decodes a binary stream of json messages where the format is a 4 byte number header followed by the json encoded
// as UTF8. This data format is used for chrome's native messaging protocol.
Stream<Object> decodeJsonStream(Stream<List<int>> stream) => new JsonStreamDecoder(stream).decode();

// Converts json to UTF8 encoded binary and adds a length header.
// This data format is used for chrome's native messaging protocol.
List<int> encodeJsonMessage(Object msg) {
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
}

class SingleResultSink implements Sink {
  bool _isClosed = false;
  var _result;

  get result {
    if (!_isClosed) throw new StateError('Sink is closed.');
    return _result;
  }

  void add(object) {
    if (_isClosed) throw new StateError('Sink is closed.');
    _result = object;
  }

  void close() { _isClosed = true; }
}
