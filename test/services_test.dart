import 'dart:convert';
import 'package:angel_framework/angel_framework.dart';
import 'package:http/http.dart' as http;
import 'package:json_god/json_god.dart' as god;
import 'package:test/test.dart';

class Todo extends Model {
  String text;
  String over;
}

main() {
  Map headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json'
  };
  Angel app;
  String url;
  http.Client client;

  setUp(() async {
    app = new Angel()
      ..use('/todos', new TypedService<Todo>(new MapService()))
      ..errorHandler = (e, req, res) {
        print('Whoops: ${e.error}');
        print(e.stackTrace);
      };

    var server = await new AngelHttp(app).startServer();
    client = new http.Client();
    url = "http://${server.address.host}:${server.port}";
  });

  tearDown(() async {
    await app.close();
    app = null;
    url = null;
    client.close();
    client = null;
  });

  group('memory', () {
    test('can index an empty service', () async {
      var response = await client.get("$url/todos/");
      print(response.body);
      expect(response.body, equals('[]'));
      print(response.body);
      expect(JSON.decode(response.body).length, 0);
    });

    test('can create data', () async {
      String postData = god.serialize({'text': 'Hello, world!'});
      var response =
          await client.post("$url/todos", headers: headers, body: postData);
      expect(response.statusCode, 201);
      var json = god.deserialize(response.body);
      print(json);
      expect(json['text'], equals('Hello, world!'));
    });

    test('can fetch data', () async {
      String postData = god.serialize({'text': 'Hello, world!'});
      await client.post("$url/todos", headers: headers, body: postData);
      var response = await client.get("$url/todos/0");
      expect(response.statusCode, 200);
      var json = god.deserialize(response.body);
      print(json);
      expect(json['text'], equals('Hello, world!'));
    });

    test('can modify data', () async {
      String postData = god.serialize({'text': 'Hello, world!'});
      await client.post("$url/todos", headers: headers, body: postData);
      postData = god.serialize({'text': 'modified'});
      var response =
          await client.patch("$url/todos/0", headers: headers, body: postData);
      expect(response.statusCode, 200);
      var json = god.deserialize(response.body);
      print(json);
      expect(json['text'], equals('modified'));
    });

    test('can overwrite data', () async {
      String postData = god.serialize({'text': 'Hello, world!'});
      await client.post("$url/todos", headers: headers, body: postData);
      postData = god.serialize({'over': 'write'});
      var response =
          await client.post("$url/todos/0", headers: headers, body: postData);
      expect(response.statusCode, 200);
      var json = god.deserialize(response.body);
      print(json);
      expect(json['text'], equals(null));
      expect(json['over'], equals('write'));
    });

    test('can delete data', () async {
      String postData = god.serialize({'text': 'Hello, world!'});
      var created = await client
          .post("$url/todos", headers: headers, body: postData)
          .then((r) => JSON.decode(r.body));
      var response = await client.delete("$url/todos/${created['id']}");
      expect(response.statusCode, 200);
      var json = god.deserialize(response.body);
      print(json);
      expect(json['text'], equals('Hello, world!'));
    });
  });
}
