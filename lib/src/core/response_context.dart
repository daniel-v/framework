library angel_framework.http.response_context;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:angel_route/angel_route.dart';
import 'package:json_god/json_god.dart' as god;
import 'package:mime/mime.dart';
import 'package:pool/pool.dart';
import '../http/http.dart';
import 'server.dart' show Angel;
import 'request_context.dart';

final RegExp _contentType =
    new RegExp(r'([^/\n]+)\/\s*([^;\n]+)\s*(;\s*charset=([^$;\n]+))?');

final RegExp _straySlashes = new RegExp(r'(^/+)|(/+$)');

/// Serializes response data into a String.
///
/// Prefer the String Function(dynamic) syntax.
@deprecated
typedef String ResponseSerializer(data);

/// A convenience wrapper around an outgoing HTTP request.
abstract class ResponseContext implements StreamSink<List<int>>, StringSink {
  final Map properties = {};
  final BytesBuilder _buffer = new _LockableBytesBuilder();
  final Map<String, String> _headers = {'server': 'angel'};

  Completer _done;
  int _statusCode = 200;

  /// The [Angel] instance that is sending a response.
  Angel app;

  /// Is `Transfer-Encoding` chunked?
  bool chunked;

  /// Any and all cookies to be sent to the user.
  final List<Cookie> cookies = [];

  /// A set of [Converter] objects that can be used to encode response data.
  ///
  /// At most one encoder will ever be used to convert data.
  final Map<String, Converter<List<int>, List<int>>> encoders = {};

  /// Points to the [RequestContext] corresponding to this response.
  RequestContext get correspondingRequest;

  @override
  Future get done => (_done ?? new Completer()).future;

  /// Headers that will be sent to the user.
  Map<String, String> get headers {
    /// If the response is closed, then this getter will return an immutable `Map`.
    if (!isOpen)
      return new Map<String, String>.unmodifiable(_headers);
    else
      return _headers;
  }

  /// Serializes response data into a String.
  ///
  /// The default is conversion into JSON via `package:json_god`.
  ///
  /// If you are 100% sure that your response handlers will only
  /// be JSON-encodable objects (i.e. primitives, `List`s and `Map`s),
  /// then consider setting [serializer] to `JSON.encode`.
  ///
  /// To set it globally for the whole [app], use the following helper:
  /// ```dart
  /// app.injectSerializer(JSON.encode);
  /// ```
  String Function(dynamic) serializer = god.serialize;

  /// This response's status code.
  int get statusCode => _statusCode;

  void set statusCode(int value) {
    if (!isOpen)
      throw closed();
    else
      _statusCode = value ?? 200;
  }

  /// Can we still write to this response?
  bool get isOpen;

  /// Returns `true` if a [Stream] is being written directly.
  bool get streaming;

  /// A set of UTF-8 encoded bytes that will be written to the response.
  BytesBuilder get buffer => _buffer;

  /// The underlying [HttpResponse] under this instance.
  HttpResponse get io;

  /// Gets the Content-Type header.
  ContentType get contentType {
    if (!headers.containsKey('content-type')) return null;

    var header = headers['content-type'];
    var match = _contentType.firstMatch(header);

    if (match == null)
      throw new Exception('Malformed Content-Type response header: "$header".');

    if (match[4]?.isNotEmpty != true)
      return new ContentType(match[1], match[2]);
    else
      return new ContentType(match[1], match[2], charset: match[4]);
  }

  /// Sets the Content-Type header.
  void set contentType(ContentType contentType) {
    headers['content-type'] = contentType.toString();
  }

  /// Set this to true if you will manually close the response.
  ///
  /// If `true`, all response finalizers will be skipped.
  bool willCloseItself = false;

  static StateError closed() => new StateError('Cannot modify a closed response.');

  /// Sends a download as a response.
  Future download(File file, {String filename}) async {
    if (!isOpen) throw closed();

    headers["Content-Disposition"] =
        'attachment; filename="${filename ?? file.path}"';
    headers['content-type'] = lookupMimeType(file.path);
    headers['content-length'] = file.lengthSync().toString();

    if (streaming) {
      await file.openRead().pipe(this);
    } else {
      buffer.add(await file.readAsBytes());
      end();
    }
  }

  /// Prevents more data from being written to the response, and locks it entire from further editing.
  ///
  /// This method should be overwritten, setting [streaming] to `false`, **after** a `super` call.
  Future close() {
    if (streaming) {
      _buffer?.clear();
    } else if (_buffer is _LockableBytesBuilder) {
      (_buffer as _LockableBytesBuilder)._lock();
    }

    if (_done?.isCompleted == false) _done.complete();
    return new Future.value();
  }

  /// Disposes of all resources.
  Future dispose() async {
    await close();
    properties.clear();
    encoders.clear();
    _buffer.clear();
    cookies.clear();
    app = null;
    _headers.clear();
    serializer = null;
  }

  /// Prevents further request handlers from running on the response, except for response finalizers.
  ///
  /// To disable response finalizers, see [willCloseItself].
  ///
  /// This method should also set [!isOpen] to true.
  void end() {
    if (_done?.isCompleted == false) _done.complete();
  }

  /// Serializes JSON to the response.
  void json(value) => serialize(value, contentType: ContentType.JSON);

  /// Returns a JSONP response.
  void jsonp(value, {String callbackName: "callback", contentType}) {
    if (!isOpen) throw closed();
    write("$callbackName(${serializer(value)})");

    if (contentType != null) {
      if (contentType is ContentType)
        this.contentType = contentType;
      else
        headers['content-type'] = contentType.toString();
    } else
      headers['content-type'] = 'application/javascript';

    end();
  }

  /// Renders a view to the response stream, and closes the response.
  Future render(String view, [Map data]) async {
    if (!isOpen) throw closed();
    write(await app.viewGenerator(view, data));
    headers['content-type'] = ContentType.HTML.toString();
    end();
  }

  /// Redirects to user to the given URL.
  ///
  /// [url] can be a `String`, or a `List`.
  /// If it is a `List`, a URI will be constructed
  /// based on the provided params.
  ///
  /// See [Router]#navigate for more. :)
  void redirect(url, {bool absolute: true, int code: 302}) {
    if (!isOpen) throw closed();
    headers
      ..['content-type'] = ContentType.HTML.toString()
      ..['location'] =
          url is String ? url : app.navigate(url, absolute: absolute);
    statusCode = code ?? 302;
    write('''
    <!DOCTYPE html>
    <html>
      <head>
        <title>Redirecting...</title>
        <meta http-equiv="refresh" content="0; url=$url">
      </head>
      <body>
        <h1>Currently redirecting you...</h1>
        <br />
        Click <a href="$url">here</a> if you are not automatically redirected...
        <script>
          window.location = "$url";
        </script>
      </body>
    </html>
    ''');
    end();
  }

  /// Redirects to the given named [Route].
  void redirectTo(String name, [Map params, int code]) {
    if (!isOpen) throw closed();
    Route _findRoute(Router r) {
      for (Route route in r.routes) {
        if (route is SymlinkRoute) {
          final m = _findRoute(route.router);

          if (m != null) return m;
        } else if (route.name == name) return route;
      }

      return null;
    }

    Route matched = _findRoute(app);

    if (matched != null) {
      redirect(matched.makeUri(params), code: code);
      return;
    }

    throw new ArgumentError.notNull('Route to redirect to ($name)');
  }

  /// Redirects to the given [Controller] action.
  void redirectToAction(String action, [Map params, int code]) {
    if (!isOpen) throw closed();
    // UserController@show
    List<String> split = action.split("@");

    if (split.length < 2)
      throw new Exception(
          "Controller redirects must take the form of 'Controller@action'. You gave: $action");

    Controller controller =
        app.controllers[split[0].replaceAll(_straySlashes, '')];

    if (controller == null)
      throw new Exception("Could not find a controller named '${split[0]}'");

    Route matched = controller.routeMappings[split[1]];

    if (matched == null)
      throw new Exception(
          "Controller '${split[0]}' does not contain any action named '${split[1]}'");

    final head =
        controller.findExpose().path.toString().replaceAll(_straySlashes, '');
    final tail = matched.makeUri(params).replaceAll(_straySlashes, '');

    redirect('$head/$tail'.replaceAll(_straySlashes, ''), code: code);
  }

  /// Copies a file's contents into the response buffer.
  Future sendFile(File file) async {
    if (!isOpen) throw closed();

    headers['content-type'] = lookupMimeType(file.path);
    buffer.add(await file.readAsBytes());
    end();
  }

  /// Serializes data to the response.
  ///
  /// [contentType] can be either a [String], or a [ContentType].
  void serialize(value, {contentType}) {
    if (!isOpen) throw closed();

    var text = serializer(value);

    if (text.isEmpty)
      return;

    if (contentType is String)
      headers['content-type'] = contentType;
    else if (contentType is ContentType) this.contentType = contentType;

    write(text);

    end();
  }

  /// Streams a file to this response.
  ///
  /// You can optionally transform the file stream with a [codec].
  Future streamFile(File file) {
    if (!isOpen) throw closed();

    headers['content-type'] = lookupMimeType(file.path);
    return file.openRead().pipe(this);
  }

  /// Releases critical resources from the [correspondingRequest].
  void releaseCorrespondingRequest() {
    if (correspondingRequest?.injections?.containsKey(Stopwatch) == true) {
      (correspondingRequest.injections[Stopwatch] as Stopwatch).stop();
    }

    if (correspondingRequest?.injections?.containsKey(PoolResource) ==
        true) {
      (correspondingRequest.injections[PoolResource] as PoolResource)
          .release();
    }
  }

  /// Configure the response to write directly to the output stream, instead of buffering.
  bool useStream();

  /// Adds a stream directly the underlying response.
  ///
  /// This will also set [willCloseItself] to `true`, thus canceling out response finalizers.
  ///
  /// If this instance has access to a [correspondingRequest], then it will attempt to transform
  /// the content using at most one of the response [encoders].
  @override
  Future addStream(Stream<List<int>> stream);

  @override
  void addError(Object error, [StackTrace stackTrace]) {
    if (_done?.isCompleted == false) _done.completeError(error, stackTrace);
  }

  /// Writes data to the response.
  void write(value, {Encoding encoding}) {
    encoding ??= UTF8;

    if (!isOpen && !streaming)
      throw closed();
    else if (streaming) {
      if (value is List<int>)
        add(value);
      else
        add(encoding.encode(value.toString()));
    } else {
      if (value is List<int>)
        buffer.add(value);
      else
        buffer.add(encoding.encode(value.toString()));
    }
  }

  @override
  void writeCharCode(int charCode) {
    if (!isOpen && !streaming)
      throw closed();
    else if (streaming)
      add([charCode]);
    else
      buffer.addByte(charCode);
  }

  @override
  void writeln([Object obj = ""]) {
    write(obj.toString());
    write('\r\n');
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    write(objects.join(separator));
  }
}

abstract class _LockableBytesBuilder extends BytesBuilder {
  factory _LockableBytesBuilder() {
    return new _LockableBytesBuilderImpl();
  }

  void _lock();
}

class _LockableBytesBuilderImpl implements _LockableBytesBuilder {
  final BytesBuilder _buf = new BytesBuilder(copy: false);
  bool _closed = false;

  StateError _deny() =>
      new StateError('Cannot modified a closed response\'s buffer.');

  @override
  void _lock() {
    _closed = true;
  }

  @override
  void add(List<int> bytes) {
    if (_closed)
      throw _deny();
    else
      _buf.add(bytes);
  }

  @override
  void addByte(int byte) {
    if (_closed)
      throw _deny();
    else
      _buf.addByte(byte);
  }

  @override
  void clear() {
    _buf.clear();
  }

  @override
  bool get isEmpty => _buf.isEmpty;

  @override
  bool get isNotEmpty => _buf.isNotEmpty;

  @override
  int get length => _buf.length;

  @override
  List<int> takeBytes() {
    return _buf.takeBytes();
  }

  @override
  List<int> toBytes() {
    return _buf.toBytes();
  }
}
