import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/generation/api_digital_twin_repository.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late Directory tempDir;
  late _FakeProxy proxy;
  late XFile front;
  late XFile side;
  late XFile back;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('humantwin_api_test');
    proxy = await _FakeProxy.start();
    front = await _photo(tempDir, 'front.jpg', _jpeg);
    side = await _photo(tempDir, 'side.png', _png);
    back = await _photo(tempDir, 'back.jpg', _jpeg);
  });

  tearDown(() async {
    await proxy.close();
    await tempDir.delete(recursive: true);
  });

  ApiDigitalTwinRepository repository({
    Uri? baseUri,
    Duration pollTimeout = const Duration(seconds: 5),
    int maxConsecutiveStatusFailures = 5,
  }) {
    final ApiDigitalTwinRepository repository = ApiDigitalTwinRepository(
      baseUri: baseUri ?? proxy.baseUri,
      modelCacheDirectory: () async => Directory('${tempDir.path}/models'),
      createTimeout: const Duration(seconds: 5),
      requestTimeout: const Duration(seconds: 5),
      defaultPollInterval: const Duration(milliseconds: 1),
      minPollInterval: Duration.zero,
      pollTimeout: pollTimeout,
      maxConsecutiveStatusFailures: maxConsecutiveStatusFailures,
    );
    addTearDown(repository.close);
    return repository;
  }

  Future<GenerationFailureKind?> failureOf(Future<Object?> operation) async {
    try {
      await operation;
    } on GenerationException catch (error) {
      return error.kind;
    }
    return null;
  }

  test(
    'creates once, polls to success, and downloads a validated GLB',
    () async {
      final List<Map<String, Object?>> statuses = <Map<String, Object?>>[
        _task('PENDING', 0),
        _task('IN_PROGRESS', 50),
        _task('SUCCEEDED', 100),
      ];
      proxy.handler = (HttpRequest request, String body) async {
        if (request.method == 'POST') {
          proxy.createBody = jsonDecode(body) as Map<String, Object?>;
          return _json(request, HttpStatus.created, _task('PENDING', 0));
        }
        if (request.uri.path.endsWith('/model.glb')) {
          return _bytes(request, HttpStatus.ok, _glb);
        }
        return _json(request, HttpStatus.ok, statuses.removeAt(0));
      };
      final ApiDigitalTwinRepository api = repository();

      final GenerationTask task = await api.createTask(
        front: front,
        side: side,
        back: back,
      );
      expect(task.id, 'fake-task-1');
      expect(task.origin, ModelOrigin.simulatedSample);
      final List<Object?> images =
          proxy.createBody!['images']! as List<Object?>;
      expect(images, hasLength(3));
      expect(images[0], 'data:image/jpeg;base64,${base64Encode(_jpeg)}');
      expect(images[1], 'data:image/png;base64,${base64Encode(_png)}');
      expect(images[2], 'data:image/jpeg;base64,${base64Encode(_jpeg)}');

      final List<int> progress = <int>[];
      final DigitalTwinModel model = await api.fetchModel(
        task,
        onProgress: progress.add,
      );
      expect(progress, <int>[0, 50, 100, 100]);
      expect(model.origin, ModelOrigin.simulatedSample);
      final File file = File.fromUri(Uri.parse(model.src));
      expect(model.src, startsWith('file://'));
      expect(await file.readAsBytes(), _glb);
      expect(
        Directory('${tempDir.path}/models').listSync().map((e) => e.path),
        <String>[file.path],
      );

      // A validated download is reused without polling or downloading again.
      final int requestsBefore = proxy.requests.length;
      final DigitalTwinModel again = await api.fetchModel(task);
      expect(again.src, model.src);
      expect(proxy.requests.length, requestsBefore);
      expect(proxy.count('POST'), 1);
    },
  );

  test('a lost create response is reported and never re-sent', () async {
    proxy.handler = (HttpRequest request, String body) async {
      final Socket socket = await request.response.detachSocket(
        writeHeaders: false,
      );
      socket.destroy();
    };

    expect(
      await failureOf(
        repository().createTask(front: front, side: side, back: back),
      ),
      GenerationFailureKind.submissionUnknown,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(proxy.requests, <String>['POST /v1/generations']);
  });

  test('an unreachable proxy fails before anything is submitted', () async {
    final HttpServer closed = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Uri unreachable = Uri.parse('http://127.0.0.1:${closed.port}');
    await closed.close(force: true);

    expect(
      await failureOf(
        repository(
          baseUri: unreachable,
        ).createTask(front: front, side: side, back: back),
      ),
      GenerationFailureKind.serviceUnavailable,
    );
  });

  test('unsupported photos are rejected before any request', () async {
    final XFile gif = await _photo(
      tempDir,
      'back.gif',
      Uint8List.fromList(ascii.encode('GIF89a-not-supported')),
    );

    expect(
      await failureOf(
        repository().createTask(front: front, side: side, back: gif),
      ),
      GenerationFailureKind.invalidPhotos,
    );
    expect(proxy.requests, isEmpty);
  });

  test('proxy creation errors map to the matching recovery path', () async {
    final Map<(int, String?), GenerationFailureKind> cases =
        <(int, String?), GenerationFailureKind>{
          (409, 'submission_unknown'):
              GenerationFailureKind.submissionUnresolved,
          (422, 'photos_rejected'): GenerationFailureKind.photosRejected,
          (400, 'invalid_photos'): GenerationFailureKind.invalidPhotos,
          (503, 'service_busy'): GenerationFailureKind.serviceUnavailable,
          (502, 'service_quota'): GenerationFailureKind.serviceRejected,
          (500, null): GenerationFailureKind.submissionUnknown,
          (201, null): GenerationFailureKind.submissionUnknown,
        };
    final ApiDigitalTwinRepository api = repository();

    for (final MapEntry<(int, String?), GenerationFailureKind> entry
        in cases.entries) {
      final (int status, String? code) = entry.key;
      proxy.handler = (HttpRequest request, String body) => _json(
        request,
        status,
        code == null
            ? <String, Object?>{'unexpected': true}
            : <String, Object?>{
                'error': <String, Object?>{'code': code, 'message': '受控错误'},
              },
      );
      expect(
        await failureOf(api.createTask(front: front, side: side, back: back)),
        entry.value,
        reason: '$status $code',
      );
    }
    expect(proxy.count('POST'), cases.length);
  });

  test('transient status errors are retried with GET only', () async {
    var statusCalls = 0;
    proxy.handler = (HttpRequest request, String body) async {
      if (request.uri.path.endsWith('/model.glb')) {
        return _bytes(request, HttpStatus.ok, _glb);
      }
      statusCalls++;
      if (statusCalls == 1) {
        return _json(
          request,
          HttpStatus.serviceUnavailable,
          _error('service_busy'),
          retryAfter: '0',
        );
      }
      if (statusCalls == 2) {
        final Socket socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.destroy();
        return;
      }
      return _json(request, HttpStatus.ok, _task('SUCCEEDED', 100));
    };

    final DigitalTwinModel model = await repository().fetchModel(_knownTask);
    expect(model.src, startsWith('file://'));
    expect(proxy.count('POST'), 0);
    expect(statusCalls, 3);
  });

  test('repeated status failures stop polling as unavailable', () async {
    proxy.handler = (HttpRequest request, String body) => _json(
      request,
      HttpStatus.serviceUnavailable,
      _error('service_unavailable'),
      retryAfter: '0',
    );

    expect(
      await failureOf(
        repository(maxConsecutiveStatusFailures: 3).fetchModel(_knownTask),
      ),
      GenerationFailureKind.statusUnavailable,
    );
    expect(proxy.count('GET'), 3);
    expect(proxy.count('POST'), 0);
  });

  test('a poll timeout can later resume the same task', () async {
    var done = false;
    proxy.handler = (HttpRequest request, String body) async {
      if (request.uri.path.endsWith('/model.glb')) {
        return _bytes(request, HttpStatus.ok, _glb);
      }
      return _json(
        request,
        HttpStatus.ok,
        done
            ? _task('SUCCEEDED', 100)
            : _task('IN_PROGRESS', 40, pollAfterMs: 20),
      );
    };
    final ApiDigitalTwinRepository api = repository(
      pollTimeout: const Duration(milliseconds: 100),
    );

    expect(
      await failureOf(api.fetchModel(_knownTask)),
      GenerationFailureKind.pollingTimedOut,
    );
    done = true;
    final DigitalTwinModel model = await api.fetchModel(_knownTask);
    expect(model.src, startsWith('file://'));
    expect(proxy.count('POST'), 0);
  });

  test('failed or missing tasks are terminal', () async {
    proxy.handler = (HttpRequest request, String body) =>
        _json(request, HttpStatus.ok, _task('FAILED', 100));
    final ApiDigitalTwinRepository api = repository();
    expect(
      await failureOf(api.fetchModel(_knownTask)),
      GenerationFailureKind.taskFailed,
    );

    proxy.handler = (HttpRequest request, String body) =>
        _json(request, HttpStatus.notFound, _error('task_not_found'));
    expect(
      await failureOf(api.fetchModel(_knownTask)),
      GenerationFailureKind.taskFailed,
    );
    expect(proxy.count('POST'), 0);
  });

  test('an invalid model is not cached and a retry downloads again', () async {
    var validModel = false;
    var modelCalls = 0;
    proxy.handler = (HttpRequest request, String body) async {
      if (request.uri.path.endsWith('/model.glb')) {
        modelCalls++;
        return _bytes(
          request,
          HttpStatus.ok,
          validModel ? _glb : Uint8List.fromList(ascii.encode('<html>')),
        );
      }
      return _json(request, HttpStatus.ok, _task('SUCCEEDED', 100));
    };
    final ApiDigitalTwinRepository api = repository();

    expect(
      await failureOf(api.fetchModel(_knownTask)),
      GenerationFailureKind.downloadFailed,
    );
    expect(modelCalls, 1);
    expect(Directory('${tempDir.path}/models').listSync(), isEmpty);

    validModel = true;
    final DigitalTwinModel model = await api.fetchModel(_knownTask);
    expect(await File.fromUri(Uri.parse(model.src)).readAsBytes(), _glb);
    expect(modelCalls, 2);
    expect(proxy.count('POST'), 0);
  });

  test('a transient download error is retried', () async {
    var modelCalls = 0;
    proxy.handler = (HttpRequest request, String body) async {
      if (request.uri.path.endsWith('/model.glb')) {
        modelCalls++;
        if (modelCalls == 1) {
          return _json(
            request,
            HttpStatus.serviceUnavailable,
            _error('service_busy'),
          );
        }
        return _bytes(request, HttpStatus.ok, _glb);
      }
      return _json(request, HttpStatus.ok, _task('SUCCEEDED', 100));
    };

    final DigitalTwinModel model = await repository().fetchModel(_knownTask);
    expect(model.src, startsWith('file://'));
    expect(modelCalls, 2);
  });
}

const GenerationTask _knownTask = GenerationTask(
  id: 'fake-task-1',
  origin: ModelOrigin.simulatedSample,
);

final Uint8List _jpeg = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  ...List<int>.filled(16, 7),
]);

final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...List<int>.filled(16, 9),
]);

final Uint8List _glb = () {
  final Uint8List bytes = Uint8List(20);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, bytes.length, Endian.little);
  return bytes;
}();

Future<XFile> _photo(Directory dir, String name, Uint8List bytes) async {
  final File file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return XFile(file.path);
}

Map<String, Object?> _task(String status, int progress, {int pollAfterMs = 0}) {
  return <String, Object?>{
    'task_id': 'fake-task-1',
    'status': status,
    'progress': progress,
    'simulated': true,
    'poll_after_ms': pollAfterMs,
  };
}

Map<String, Object?> _error(String code) {
  return <String, Object?>{
    'error': <String, Object?>{
      'code': code,
      'message': '受控错误',
      'retryable': true,
    },
  };
}

Future<void> _json(
  HttpRequest request,
  int status,
  Map<String, Object?> body, {
  String? retryAfter,
}) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  if (retryAfter != null) {
    request.response.headers.set(HttpHeaders.retryAfterHeader, retryAfter);
  }
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> _bytes(HttpRequest request, int status, Uint8List bytes) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.binary;
  request.response.add(bytes);
  await request.response.close();
}

typedef _Handler = Future<void> Function(HttpRequest request, String body);

class _FakeProxy {
  _FakeProxy._(this._server) {
    _server.listen((HttpRequest request) async {
      final String body = await utf8.decodeStream(request);
      requests.add('${request.method} ${request.uri.path}');
      await handler(request, body);
    });
  }

  static Future<_FakeProxy> start() async {
    return _FakeProxy._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  }

  final HttpServer _server;
  final List<String> requests = <String>[];
  Map<String, Object?>? createBody;
  _Handler handler = (HttpRequest request, String body) =>
      _json(request, HttpStatus.notFound, _error('not_found'));

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  int count(String method) {
    return requests.where((String line) => line.startsWith('$method ')).length;
  }

  Future<void> close() => _server.close(force: true);
}
