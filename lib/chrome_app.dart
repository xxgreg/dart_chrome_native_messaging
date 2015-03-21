library chrome_native_messaging.chrome_app;

import 'dart:async';
import 'json_channel.dart';
import 'package:chrome/chrome_app.dart';

export 'json_channel.dart';

class ChromeAppJsonChannel implements JsonChannel {

  bool _connected = true;
  final Port _port;
  final StreamController<Object> _onMessage = new StreamController<Object>();

  ChromeAppJsonChannel(String nativeMessagingHostName)
      : _port = runtime.connectNative(nativeMessagingHostName) {

    _port.onMessage.listen(null)
      ..onData((e) { _onMessage.add(e.message); })
      ..onDone(() {
        _connected = false;
        close();
      })
      ..onError((e) { _onMessage.addError(e); });

  }

  /// Return an object deserialised from json.
  Stream<Object> get onMessage => _onMessage.stream;

  /// The argument must be a data structure containing only the types List, Map, String, num, or bool.
  Future send(Object json) {
    _port.postMessage(json);
    return new Future.value();
  }

  /// It is safe to call close on an already closed channel.
  void close() {
    if (_connected) _port.disconnect();
    _connected = false;
    if (!_onMessage.isClosed) _onMessage.close();
  }

}
