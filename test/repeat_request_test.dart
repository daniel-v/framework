import 'dart:async';
import 'dart:convert';
import 'package:angel_framework/angel_framework.dart';
import 'package:mock_request/mock_request.dart';
import 'package:test/test.dart';

main() {
  MockHttpRequest mk(int id) {
    return new MockHttpRequest('GET', Uri.parse('/test/$id'))..close();
  }

  test('can request the same url twice', () async {
    var app = new Angel()..get('/test/:id', (id) => 'Hello $id');
    var rq1 = mk(1), rq2 = mk(2), rq3 = mk(1);
    await Future.wait([rq1, rq2, rq3].map(new AngelHttp(app).handleRequest));
    var body1 = await rq1.response.transform(UTF8.decoder).join(),
        body2 = await rq2.response.transform(UTF8.decoder).join(),
        body3 = await rq3.response.transform(UTF8.decoder).join();
    print('Response #1: $body1');
    print('Response #2: $body2');
    print('Response #3: $body3');
    expect(
        body1,
        allOf(
          isNot(body2),
          equals(body3),
        ));
  });
}
