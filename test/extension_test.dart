import 'dart:async';
import 'package:angel_framework/angel_framework.dart';
import 'package:mock_request/mock_request.dart';
import 'package:test/test.dart';

final Uri ENDPOINT = Uri.parse('http://example.com');

main() {
  test('single extension', () async {
    var req = await makeRequest('foo.js');
    expect(req.extension, '.js');
  });

  test('multiple extensions', () async {
    var req = await makeRequest('foo.min.js');
    expect(req.extension, '.js');
  });

  test('no extension', () async {
    var req = await makeRequest('foo');
    expect(req.extension, '');
  });
}

Future<RequestContext> makeRequest(String path) {
  var rq = new MockHttpRequest('GET', ENDPOINT.replace(path: path))..close();
  var app = new Angel();
  var http = new AngelHttp(app);
  return http.createRequestContext(rq);
}
