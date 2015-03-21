// Copyright (c) 2015, Greg Lowe. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library chrome_native_messaging;

import 'dart:async';

abstract class JsonChannel {
  Future send(Object json);
  Stream<Object> get onMessage;
  void close();
}
