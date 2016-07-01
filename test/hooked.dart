import 'package:angel_framework/angel_framework.dart';
import 'package:http/http.dart' as http;
import 'package:json_god/json_god.dart' as god;
import 'package:test/test.dart';
import 'common.dart';

main() {
  group('Hooked', () {
    Map headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    };
    Angel app;
    String url;
    http.Client client;
    HookedService Todos;

    setUp(() async {
      app = new Angel();
      client = new http.Client();
      app.use('/todos', new MemoryService<Todo>());
      Todos = app.service("todos");

      await app.startServer(null, 0);
      url = "http://${app.httpServer.address.host}:${app.httpServer.port}";
    });

    tearDown(() async {
      app = null;
      url = null;
      client.close();
      client = null;
      Todos = null;
    });

    test("listen before and after", () async {
      int count = 0;

      Todos
        ..beforeIndexed.listen((_) {
          count++;
        })
        ..afterIndexed.listen((_) {
          count++;
        });

      var response = await client.get("$url/todos");
      print(response.body);
      expect(count, equals(2));
    });

    test("cancel before", () async {
      Todos.beforeCreated..listen((HookedServiceEvent event) {
        event.cancel({"hello": "hooked world"});
      })..listen((HookedServiceEvent event) {
        event.cancel({"this_hook": "should never run"});
      });

      var response = await client.post(
          "$url/todos", body: god.serialize({"arbitrary": "data"}),
          headers: headers);
      print(response.body);
      Map result = god.deserialize(response.body);
      expect(result["hello"], equals("hooked world"));
    });

    test("cancel after", () async {
      Todos.afterIndexed..listen((HookedServiceEvent event) async {
        // Hooks can be Futures ;)
        event.cancel([{"angel": "framework"}]);
      })..listen((HookedServiceEvent event) {
        event.cancel({"this_hook": "should never run either"});
      });

      var response = await client.get("$url/todos");
      print(response.body);
      List result = god.deserialize(response.body);
      expect(result[0]["angel"], equals("framework"));
    });
  });
}