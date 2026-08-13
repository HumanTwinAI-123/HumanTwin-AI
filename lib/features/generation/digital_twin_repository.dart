import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

abstract class DigitalTwinRepository {
  Future<void> generateDigitalTwin({
    required XFile front,
    required XFile side,
    required XFile back,
  });
}

final digitalTwinRepositoryProvider = Provider<DigitalTwinRepository>(
  (Ref ref) => MockDigitalTwinRepository(),
);

class MockDigitalTwinRepository implements DigitalTwinRepository {
  MockDigitalTwinRepository({
    this.delay = const Duration(milliseconds: 2400),
    this.shouldFail = false,
  });

  final Duration delay;
  final bool shouldFail;
  int callCount = 0;

  @override
  Future<void> generateDigitalTwin({
    required XFile front,
    required XFile side,
    required XFile back,
  }) async {
    callCount++;
    await Future<void>.delayed(delay);
    if (shouldFail) {
      throw StateError('Mock digital twin generation failed');
    }
  }
}
