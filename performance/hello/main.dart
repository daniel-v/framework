/// A basic server that prints "Hello, world!"
library performance.hello;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:angel_framework/angel_framework.dart';

main() async {
  var isolates = <Isolate>[];

  for (int i = 0; i < Platform.numberOfProcessors; i++) {
    isolates.add(await Isolate.spawn(start, i + 1));
  }

  await Future.wait(isolates.map((i) {
    var rcv = new ReceivePort();
    i.addOnExitListener(rcv.sendPort);
    return rcv.first;
  }));
  //start(0);
}

void start(int id) {
  var app = new Angel()..lazyParseBodies = true;
  var http = new AngelHttp.custom(app, startShared);

    app.get('/', (req, ResponseContext res) {
      res.willCloseItself = true;
      res.io
        ..write('Hello, world!')
        ..close();
      return false;
    });


  var oldHandler = app.errorHandler;
  app.errorHandler = (e, req, res) {
    print('Oops: ${e.error ?? e}');
    print(e.stackTrace);
    return oldHandler(e, req, res);
  };

  http.startServer(InternetAddress.LOOPBACK_IP_V4, 3000).then((server) {
    print(
        'Instance #$id listening at http://${server.address.address}:${server.port}');
  });
}
