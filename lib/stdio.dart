library chrome_native_messaging.stdio;

import 'dart:async';
import 'dart:io';

import 'json_channel.dart';
export 'json_channel.dart';
import 'src/json_stream.dart' show decodeJsonStream, encodeJsonMessage;
export 'src/json_stream.dart' show decodeJsonStream, encodeJsonMessage;


class StdioJsonChannel implements JsonChannel {

  final StreamController<Object> _onMessage = new StreamController<Object>();

  StdioJsonChannel()
      : onMessage = decodeJsonStream(stdin) {
    stdin.lineMode = false;
  }

  /// Return an object deserialised from json.
  final Stream<Object> onMessage;

  //TODO would be nice to return a future from stdout.flush(). This is actually hard to implement without
  // making things crashy, as flush cannot be called concurrently.
  /// The argument must be a data structure containing only the types List, Map, String, num, or bool.
  void send(Object json) {
    var bytes = encodeJsonMessage(json);
    stdout.add(bytes);
  }

  /// It is safe to call close on an already closed channel.
  void close() {
    if (!_onMessage.isClosed) _onMessage.close();
  }

}

