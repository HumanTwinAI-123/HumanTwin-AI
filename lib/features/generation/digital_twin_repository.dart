import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'api_digital_twin_repository.dart';

/// Non-secret base URL of the local generation proxy, e.g.
/// `--dart-define=HUMANTWIN_API_BASE_URL=http://127.0.0.1:8787`.
/// Empty (the default) keeps the offline Mock repository.
const String humanTwinApiBaseUrl = String.fromEnvironment(
  'HUMANTWIN_API_BASE_URL',
);

const String sampleModelAsset = 'assets/models/human_demo.glb';
const String sampleModelAssetId = 'humantwin-avatar-v2';
const String sampleModelSource = 'makehuman-core-cc0-blender-remodel';
const String sampleModelAttribution = 'HumanTwin AI 示例模型 · MakeHuman / Blender';
const String sampleModelCopyright =
    'MakeHuman Community official core assets (CC0-1.0). Body shaping, garment fitting, '
    'material refinement and export by HumanTwin AI in Blender. '
    'Synthetic demonstration model; no user photos.';

/// Where a model comes from, so the UI never implies a reconstruction.
enum ModelOrigin {
  /// Simulated generation that always yields the bundled sample model.
  simulatedSample,

  /// A model returned by a real generation service for the submitted photos.
  serviceGenerated,
}

@immutable
class GenerationTask {
  const GenerationTask({required this.id, required this.origin});

  final String id;
  final ModelOrigin origin;
}

@immutable
class DigitalTwinModel {
  const DigitalTwinModel({required this.src, required this.origin});

  /// The bundled sample model shown by Mock mode and direct Viewer entry.
  static const DigitalTwinModel sample = DigitalTwinModel(
    src: sampleModelAsset,
    origin: ModelOrigin.simulatedSample,
  );

  /// A Flutter asset key or a `file://` URI that the Viewer can load.
  final String src;
  final ModelOrigin origin;
}

enum GenerationFailureKind {
  /// Photos failed local or proxy checks; nothing was created.
  invalidPhotos,

  /// The service refused the photos; nothing was created.
  photosRejected,

  /// The service could not be reached or was busy; nothing was created.
  serviceUnavailable,

  /// The service refused the request (credentials or quota).
  serviceRejected,

  /// The create response was lost, so a task may exist.
  submissionUnknown,

  /// The proxy itself could not confirm an upstream creation.
  submissionUnresolved,

  /// The task finished without a model or no longer exists.
  taskFailed,

  /// The task was still running when polling stopped.
  pollingTimedOut,

  /// Task status was temporarily unavailable.
  statusUnavailable,

  /// The finished model could not be downloaded or validated.
  downloadFailed,
}

class GenerationException implements Exception {
  const GenerationException(this.kind);

  final GenerationFailureKind kind;

  @override
  String toString() => 'GenerationException(${kind.name})';
}

abstract class DigitalTwinRepository {
  /// Submits the ordered photos and returns the created task.
  ///
  /// Implementations never retry creation on their own: a lost response must
  /// surface as [GenerationFailureKind.submissionUnknown].
  Future<GenerationTask> createTask({
    required XFile front,
    required XFile side,
    required XFile back,
  });

  /// Waits for [task] to finish and returns a model the Viewer can load.
  ///
  /// Safe to call again for the same task: it only polls and downloads.
  Future<DigitalTwinModel> fetchModel(
    GenerationTask task, {
    ValueChanged<int>? onProgress,
  });
}

final digitalTwinRepositoryProvider = Provider<DigitalTwinRepository>((
  Ref ref,
) {
  if (humanTwinApiBaseUrl.isEmpty) {
    return MockDigitalTwinRepository();
  }
  final ApiDigitalTwinRepository repository = ApiDigitalTwinRepository(
    baseUri: Uri.parse(humanTwinApiBaseUrl),
  );
  ref.onDispose(repository.close);
  return repository;
});

class MockDigitalTwinRepository implements DigitalTwinRepository {
  MockDigitalTwinRepository({
    this.delay = const Duration(seconds: 5),
    this.shouldFail = false,
  });

  final Duration delay;
  final bool shouldFail;
  int createCount = 0;
  int fetchCount = 0;

  @override
  Future<GenerationTask> createTask({
    required XFile front,
    required XFile side,
    required XFile back,
  }) async {
    createCount++;
    return GenerationTask(
      id: 'mock-$createCount',
      origin: ModelOrigin.simulatedSample,
    );
  }

  @override
  Future<DigitalTwinModel> fetchModel(
    GenerationTask task, {
    ValueChanged<int>? onProgress,
  }) async {
    fetchCount++;
    // Simulated progress so the UI can show 「模拟生成中 · n%」; nothing is reconstructed.
    const int steps = 20;
    for (int step = 1; step <= steps; step++) {
      await Future<void>.delayed(delay ~/ steps);
      if (shouldFail && step >= steps * 0.4) {
        throw StateError('Mock digital twin generation failed');
      }
      if (step < steps) {
        onProgress?.call(step * 100 ~/ steps);
      }
    }
    return DigitalTwinModel.sample;
  }
}
