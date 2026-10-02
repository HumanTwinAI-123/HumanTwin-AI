import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'digital_twin_repository.dart';

typedef ModelCacheDirectory = Future<Directory> Function();

/// Talks to the local generation proxy (see `docs/meshy-api.md`).
///
/// The proxy owns provider credentials and de-duplicates paid task creation
/// by photo content. This client adds the other half of that guarantee: it
/// never re-sends a creation request on its own, and polling or download
/// retries only issue GET requests for an already known task.
class ApiDigitalTwinRepository implements DigitalTwinRepository {
  ApiDigitalTwinRepository({
    required this.baseUri,
    HttpClient? httpClient,
    ModelCacheDirectory? modelCacheDirectory,
    this.createTimeout = const Duration(seconds: 90),
    this.requestTimeout = const Duration(seconds: 20),
    this.modelResponseTimeout = const Duration(seconds: 150),
    this.downloadIdleTimeout = const Duration(seconds: 30),
    this.pollTimeout = const Duration(minutes: 10),
    this.defaultPollInterval = const Duration(seconds: 5),
    this.minPollInterval = const Duration(milliseconds: 500),
    this.maxPollInterval = const Duration(seconds: 30),
    this.maxConsecutiveStatusFailures = 5,
    this.maxDownloadAttempts = 3,
  }) : _client =
           httpClient ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 10)),
       _modelCacheDirectory = modelCacheDirectory ?? _defaultModelDirectory;

  static const int maxPhotoBytes = 8 * 1024 * 1024;
  static const int maxModelBytes = 64 * 1024 * 1024;
  static const int _maxJsonBytes = 64 * 1024;
  static final RegExp _taskIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final Uri baseUri;
  final Duration createTimeout;
  final Duration requestTimeout;

  /// The proxy may fetch the model from the provider before it responds.
  final Duration modelResponseTimeout;
  final Duration downloadIdleTimeout;
  final Duration pollTimeout;
  final Duration defaultPollInterval;
  final Duration minPollInterval;
  final Duration maxPollInterval;
  final int maxConsecutiveStatusFailures;
  final int maxDownloadAttempts;

  final HttpClient _client;
  final ModelCacheDirectory _modelCacheDirectory;
  var _downloadSequence = 0;

  void close() => _client.close(force: true);

  @override
  Future<GenerationTask> createTask({
    required XFile front,
    required XFile side,
    required XFile back,
  }) async {
    _checkConfigured();
    final List<Uint8List> images = <Uint8List>[
      await _photoDataUri(front),
      await _photoDataUri(side),
      await _photoDataUri(back),
    ];

    final HttpClientRequest request;
    try {
      request = await _client.postUrl(_endpoint(<String>['generations']));
      request.persistentConnection = false;
    } on Object {
      // No connection was opened, so nothing was submitted.
      throw const GenerationException(GenerationFailureKind.serviceUnavailable);
    }

    final _JsonResponse response;
    try {
      _writeCreateBody(request, images);
      response = await _readJson(request).timeout(
        createTimeout,
        onTimeout: () {
          request.abort();
          throw TimeoutException('create request');
        },
      );
    } on Object {
      // The body may have reached the proxy: never resubmit automatically.
      throw const GenerationException(GenerationFailureKind.submissionUnknown);
    }

    if (response.statusCode == HttpStatus.ok ||
        response.statusCode == HttpStatus.created) {
      final _TaskStatus? status = _taskStatusFrom(response.body);
      if (status == null) {
        throw const GenerationException(
          GenerationFailureKind.submissionUnknown,
        );
      }
      return GenerationTask(id: status.taskId, origin: status.origin);
    }
    throw GenerationException(_createFailureKind(response));
  }

  @override
  Future<DigitalTwinModel> fetchModel(
    GenerationTask task, {
    ValueChanged<int>? onProgress,
  }) async {
    _checkConfigured();
    if (!_taskIdPattern.hasMatch(task.id)) {
      throw const GenerationException(GenerationFailureKind.taskFailed);
    }
    final File modelFile;
    try {
      final Directory directory = await _modelCacheDirectory();
      await directory.create(recursive: true);
      modelFile = File('${directory.path}/${task.id}.glb');
    } on Object {
      throw const GenerationException(GenerationFailureKind.downloadFailed);
    }

    // A validated download is reused, e.g. when Processing is re-entered.
    if (!await _isValidGlb(modelFile)) {
      await _waitForSuccess(task, onProgress);
      await _download(task, modelFile);
    }
    onProgress?.call(100);
    return DigitalTwinModel(
      src: Uri.file(modelFile.path).toString(),
      origin: task.origin,
    );
  }

  Future<void> _waitForSuccess(
    GenerationTask task,
    ValueChanged<int>? onProgress,
  ) async {
    final Stopwatch elapsed = Stopwatch()..start();
    var consecutiveFailures = 0;
    while (true) {
      _JsonResponse? response;
      try {
        response = await _getJson(_endpoint(<String>['generations', task.id]));
      } on Object {
        response = null;
      }

      Duration wait;
      final _TaskStatus? status = response?.statusCode == HttpStatus.ok
          ? _taskStatusFrom(response!.body)
          : null;
      if (status != null && status.taskId == task.id) {
        consecutiveFailures = 0;
        onProgress?.call(status.progress);
        switch (status.status) {
          case 'SUCCEEDED':
            return;
          case 'FAILED':
          case 'CANCELED':
            throw const GenerationException(GenerationFailureKind.taskFailed);
        }
        wait = status.pollAfter ?? defaultPollInterval;
      } else {
        final GenerationFailureKind? permanent = _permanentStatusFailure(
          response,
        );
        if (permanent != null) {
          throw GenerationException(permanent);
        }
        consecutiveFailures++;
        if (consecutiveFailures >= maxConsecutiveStatusFailures) {
          throw const GenerationException(
            GenerationFailureKind.statusUnavailable,
          );
        }
        wait =
            response?.retryAfter ??
            defaultPollInterval * (1 << (consecutiveFailures - 1).clamp(0, 3));
      }

      wait = _clampPoll(wait);
      if (elapsed.elapsed + wait > pollTimeout) {
        throw const GenerationException(GenerationFailureKind.pollingTimedOut);
      }
      await Future<void>.delayed(wait);
    }
  }

  Future<void> _download(GenerationTask task, File target) async {
    final Uri uri = _endpoint(<String>['generations', task.id, 'model.glb']);
    for (var attempt = 1; ; attempt++) {
      try {
        await _downloadOnce(uri, target);
        return;
      } on _InvalidModel {
        throw const GenerationException(GenerationFailureKind.downloadFailed);
      } on Object {
        if (attempt >= maxDownloadAttempts) {
          throw const GenerationException(GenerationFailureKind.downloadFailed);
        }
        await Future<void>.delayed(_clampPoll(defaultPollInterval));
      }
    }
  }

  Future<void> _downloadOnce(Uri uri, File target) async {
    // Unique part files keep concurrent downloads of one task from colliding.
    final File partial = File('${target.path}.${_downloadSequence++}.part');
    final HttpClientRequest request = await _client.getUrl(uri)
      ..persistentConnection = false;
    IOSink? sink;
    try {
      final HttpClientResponse response = await request.close().timeout(
        modelResponseTimeout,
      );
      if (response.statusCode != HttpStatus.ok) {
        final bool retryable =
            response.statusCode == HttpStatus.conflict ||
            response.statusCode == HttpStatus.tooManyRequests ||
            response.statusCode >= 500;
        await response.drain<void>().catchError((Object _) {});
        if (retryable) {
          throw const HttpException('model temporarily unavailable');
        }
        throw const _InvalidModel();
      }
      if (response.contentLength > maxModelBytes) {
        throw const _InvalidModel();
      }
      sink = partial.openWrite();
      var received = 0;
      await for (final List<int> chunk in response.timeout(
        downloadIdleTimeout,
      )) {
        received += chunk.length;
        if (received > maxModelBytes) {
          throw const _InvalidModel();
        }
        sink.add(chunk);
      }
      await sink.close();
      sink = null;
      if (!await _isValidGlb(partial)) {
        throw const _InvalidModel();
      }
      await partial.rename(target.path);
    } finally {
      request.abort();
      try {
        await sink?.close();
        if (await partial.exists()) {
          await partial.delete();
        }
      } on FileSystemException {
        // Best-effort cleanup; the next attempt uses a new part file.
      }
    }
  }

  Future<_JsonResponse> _getJson(Uri uri) async {
    final HttpClientRequest request = await _client.getUrl(uri)
      ..persistentConnection = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    return _readJson(request).timeout(
      requestTimeout,
      onTimeout: () {
        request.abort();
        throw TimeoutException('status request');
      },
    );
  }

  Future<_JsonResponse> _readJson(HttpClientRequest request) async {
    final HttpClientResponse response = await request.close();
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      bytes.add(chunk);
      if (bytes.length > _maxJsonBytes) {
        throw const FormatException('Response too large');
      }
    }
    Map<String, Object?>? body;
    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      body = decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      body = null;
    }
    final int? retryAfterSeconds = int.tryParse(
      response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
    );
    return _JsonResponse(
      statusCode: response.statusCode,
      body: body,
      retryAfter: retryAfterSeconds == null || retryAfterSeconds < 0
          ? null
          : Duration(seconds: retryAfterSeconds),
    );
  }

  void _writeCreateBody(HttpClientRequest request, List<Uint8List> images) {
    final Uint8List prefix = ascii.encode('{"images":["');
    final Uint8List separator = ascii.encode('","');
    final Uint8List suffix = ascii.encode('"]}');
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.contentLength =
        prefix.length +
        separator.length * (images.length - 1) +
        suffix.length +
        images.fold<int>(0, (int total, Uint8List image) {
          return total + image.length;
        });
    request.add(prefix);
    for (var index = 0; index < images.length; index++) {
      if (index > 0) {
        request.add(separator);
      }
      request.add(images[index]);
    }
    request.add(suffix);
  }

  /// Returns the photo as ASCII `data:` URI bytes after checking its type.
  Future<Uint8List> _photoDataUri(XFile photo) async {
    final Uint8List bytes;
    try {
      final int length = await photo.length();
      if (length <= 0 || length > maxPhotoBytes) {
        throw const GenerationException(GenerationFailureKind.invalidPhotos);
      }
      bytes = await photo.readAsBytes();
    } on Object {
      throw const GenerationException(GenerationFailureKind.invalidPhotos);
    }
    final String? mimeType = _imageMimeType(bytes);
    if (mimeType == null || bytes.length > maxPhotoBytes) {
      throw const GenerationException(GenerationFailureKind.invalidPhotos);
    }
    return ascii.encode('data:$mimeType;base64,${base64Encode(bytes)}');
  }

  void _checkConfigured() {
    if (!baseUri.hasAuthority ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw const GenerationException(GenerationFailureKind.serviceRejected);
    }
  }

  Uri _endpoint(List<String> segments) {
    return baseUri.replace(
      pathSegments: <String>[
        ...baseUri.pathSegments.where((String segment) => segment.isNotEmpty),
        'v1',
        ...segments,
      ],
    );
  }

  Duration _clampPoll(Duration value) {
    if (value < minPollInterval) {
      return minPollInterval;
    }
    return value > maxPollInterval ? maxPollInterval : value;
  }

  _TaskStatus? _taskStatusFrom(Map<String, Object?>? body) {
    final Object? taskId = body?['task_id'];
    final Object? status = body?['status'];
    final Object? progress = body?['progress'];
    final Object? simulated = body?['simulated'];
    if (taskId is! String ||
        !_taskIdPattern.hasMatch(taskId) ||
        status is! String ||
        !_taskStatuses.contains(status) ||
        simulated is! bool) {
      return null;
    }
    final Object? pollAfterMs = body?['poll_after_ms'];
    return _TaskStatus(
      taskId: taskId,
      status: status,
      progress: progress is int ? progress.clamp(0, 100) : 0,
      origin: simulated
          ? ModelOrigin.simulatedSample
          : ModelOrigin.serviceGenerated,
      pollAfter: pollAfterMs is int && pollAfterMs >= 0
          ? Duration(milliseconds: pollAfterMs)
          : null,
    );
  }

  static GenerationFailureKind _createFailureKind(_JsonResponse response) {
    return switch (response.errorCode) {
      'invalid_photos' ||
      'payload_too_large' => GenerationFailureKind.invalidPhotos,
      'photos_rejected' => GenerationFailureKind.photosRejected,
      'service_busy' ||
      'service_unavailable' => GenerationFailureKind.serviceUnavailable,
      'submission_unknown' => GenerationFailureKind.submissionUnresolved,
      'service_auth' ||
      'service_quota' ||
      'forbidden' ||
      'invalid_request' => GenerationFailureKind.serviceRejected,
      _ when response.statusCode >= 500 =>
        // An unexplained server error may have happened after creation.
        GenerationFailureKind.submissionUnknown,
      _ => GenerationFailureKind.serviceRejected,
    };
  }

  /// Status errors that polling the same task again cannot fix.
  static GenerationFailureKind? _permanentStatusFailure(
    _JsonResponse? response,
  ) {
    if (response == null) {
      return null;
    }
    return switch (response.errorCode) {
      'task_not_found' || 'upstream_error' => GenerationFailureKind.taskFailed,
      'service_auth' ||
      'service_quota' ||
      'forbidden' => GenerationFailureKind.serviceRejected,
      _ => null,
    };
  }

  static String? _imageMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    const List<int> png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length >= png.length) {
      for (var index = 0; index < png.length; index++) {
        if (bytes[index] != png[index]) {
          return null;
        }
      }
      return 'image/png';
    }
    return null;
  }

  static Future<bool> _isValidGlb(File file) async {
    try {
      final int length = await file.length();
      if (length < 12 || length > maxModelBytes) {
        return false;
      }
      final RandomAccessFile handle = await file.open();
      final Uint8List header;
      try {
        header = await handle.read(12);
      } finally {
        await handle.close();
      }
      final ByteData view = ByteData.sublistView(header);
      return header.length == 12 &&
          view.getUint32(0, Endian.little) == 0x46546C67 && // "glTF"
          view.getUint32(4, Endian.little) == 2 &&
          view.getUint32(8, Endian.little) == length;
    } on Object {
      return false;
    }
  }

  static Future<Directory> _defaultModelDirectory() async {
    return Directory('${Directory.systemTemp.path}/humantwin_models');
  }
}

const Set<String> _taskStatuses = <String>{
  'PENDING',
  'IN_PROGRESS',
  'SUCCEEDED',
  'FAILED',
  'CANCELED',
};

class _JsonResponse {
  const _JsonResponse({
    required this.statusCode,
    required this.body,
    required this.retryAfter,
  });

  final int statusCode;
  final Map<String, Object?>? body;
  final Duration? retryAfter;

  String? get errorCode {
    final Object? error = body?['error'];
    if (error is Map<String, Object?>) {
      final Object? code = error['code'];
      return code is String ? code : null;
    }
    return null;
  }
}

class _TaskStatus {
  const _TaskStatus({
    required this.taskId,
    required this.status,
    required this.progress,
    required this.origin,
    required this.pollAfter,
  });

  final String taskId;
  final String status;
  final int progress;
  final ModelOrigin origin;
  final Duration? pollAfter;
}

class _InvalidModel implements Exception {
  const _InvalidModel();
}
