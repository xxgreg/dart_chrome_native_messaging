library chrome_native_messaging.test;

import 'dart:async';
import 'dart:convert';

import 'package:unittest/unittest.dart';
import 'package:chrome_native_messaging/stdio.dart';

main() async {

  test('single', testSingle);
  test('multiple', testMultiple);
  test('single split', testSingleSplit);
  test('multiple split', testMultipleSplit);
  test('multiple split 2', testMultipleSplit2);

}


testSingle() async {
  var msg = {"foo": "bar"};
  var bytes = encodeJsonMessage(msg);
  var stream = new Stream.fromIterable([bytes]);
  var result = await decodeJsonStream(stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg])));
}

testMultiple() async {
  var msg1 = {"foo": "bar"};
  var msg2 = {"bob": 42};

  var bytes = new List<int>()
    ..addAll(encodeJsonMessage(msg1))
    ..addAll(encodeJsonMessage(msg2));

  var stream = new Stream.fromIterable([bytes]);
  var result = await decodeJsonStream(stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg1, msg2])));
}


testSingleSplit() async {
  var msg = {"foo": "bar"};
  var bytes = encodeJsonMessage(msg);

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
    ..addAll(encodeJsonMessage(msg1))
    ..addAll(encodeJsonMessage(msg2));

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
    ..addAll(encodeJsonMessage(msg1))
    ..addAll(encodeJsonMessage(msg2));

  var ctl = new StreamController<List<int>>();

  // Split message into chunks.
  ctl.add(bytes.take(6).toList());
  ctl.add(bytes.skip(6).take(2).toList());
  ctl.add(bytes.skip(8).toList());
  ctl.close();

  var result = await decodeJsonStream(ctl.stream).toList();

  expect(JSON.encode(result), equals(JSON.encode([msg1, msg2])));
}

