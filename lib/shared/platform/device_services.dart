import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-private locations reported by the platform.
class DevicePaths {
  const DevicePaths({
    required this.documents,
    required this.cache,
    required this.sdkInt,
    String? pickerCache,
  }) : pickerCache = pickerCache ?? cache;

  /// Persistent app-private directory, excluded from system backup.
  final String documents;
  final String cache;

  /// Where the image picker leaves its copies (Android: the cache; iOS: the temp directory).
  final String pickerCache;

  /// Android API level; 0 on other platforms.
  final int sdkInt;
}

enum ShareStatus { handedOff, closed, failed }

class ShareOutcome {
  const ShareOutcome(this.status, {this.appLabel});

  final ShareStatus status;

  /// The app Android reported as chosen, when it reports one.
  final String? appLabel;
}

enum SaveStatus { saved, cancelled, unsupported, failed }

class SaveOutcome {
  const SaveOutcome(this.status, {this.location});

  final SaveStatus status;
  final String? location;
}

/// Platform services used by the local v1. Nothing here uploads or contacts a server.
abstract class DeviceServices {
  Future<DevicePaths> paths();

  /// Opens the system share sheet for a file the app exported.
  Future<ShareOutcome> shareFile(String path, {required String mimeType});

  /// System "save as" (Android Storage Access Framework / iOS Files). Needs no permission.
  Future<SaveOutcome> saveDocument(
    String path, {
    required String fileName,
    required String mimeType,
  });

  /// Saves a PNG to the gallery (Android 10+ only; otherwise [SaveStatus.unsupported]).
  Future<SaveOutcome> saveImageToGallery(
    String path, {
    required String fileName,
  });
}

class MethodChannelDeviceServices implements DeviceServices {
  MethodChannelDeviceServices([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('humantwin/device');

  final MethodChannel _channel;

  @override
  Future<DevicePaths> paths() async {
    final Map<Object?, Object?> result =
        await _channel.invokeMethod<Map<Object?, Object?>>('paths') ??
        const <Object?, Object?>{};
    return DevicePaths(
      documents: result['documents']! as String,
      cache: result['cache']! as String,
      pickerCache: result['pickerCache'] as String?,
      sdkInt: (result['sdkInt'] as int?) ?? 0,
    );
  }

  @override
  Future<ShareOutcome> shareFile(
    String path, {
    required String mimeType,
  }) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMethod<Map<Object?, Object?>>('shareFile', <String, Object>{
            'path': path,
            'mimeType': mimeType,
          });
      return switch (result?['status']) {
        'handedOff' => ShareOutcome(
          ShareStatus.handedOff,
          appLabel: result?['app'] as String?,
        ),
        'closed' => const ShareOutcome(ShareStatus.closed),
        _ => const ShareOutcome(ShareStatus.failed),
      };
    } on PlatformException {
      return const ShareOutcome(ShareStatus.failed);
    }
  }

  @override
  Future<SaveOutcome> saveDocument(
    String path, {
    required String fileName,
    required String mimeType,
  }) async {
    return _save('saveDocument', <String, Object>{
      'path': path,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }

  @override
  Future<SaveOutcome> saveImageToGallery(
    String path, {
    required String fileName,
  }) {
    return _save('saveImageToGallery', <String, Object>{
      'path': path,
      'fileName': fileName,
    });
  }

  Future<SaveOutcome> _save(String method, Map<String, Object> args) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMethod<Map<Object?, Object?>>(method, args);
      final String? location = result?['location'] as String?;
      return switch (result?['status']) {
        'saved' => SaveOutcome(SaveStatus.saved, location: location),
        'cancelled' => const SaveOutcome(SaveStatus.cancelled),
        'unsupported' => const SaveOutcome(SaveStatus.unsupported),
        _ => const SaveOutcome(SaveStatus.failed),
      };
    } on PlatformException {
      return const SaveOutcome(SaveStatus.failed);
    }
  }
}

final deviceServicesProvider = Provider<DeviceServices>(
  (Ref ref) => MethodChannelDeviceServices(),
);

/// Android API level of the running device (0 elsewhere); overridden at startup.
final deviceSdkIntProvider = Provider<int>((Ref ref) => 0);
