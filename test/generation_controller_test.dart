import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/generation/generation_controller.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test(
    'starts idle and successful generation preserves the photo state',
    () async {
      final XFile front = XFile('/photos/front.jpg');
      final XFile side = XFile('/photos/side.jpg');
      final XFile back = XFile('/photos/back.jpg');
      final Completer<void> completion = Completer<void>();
      final _ControlledRepository repository = _ControlledRepository(
        completions: <Future<void>>[completion.future],
      );
      final ProviderContainer container = _container(
        repository: repository,
        photoState: PhotoFlowState(front: front, side: side, back: back),
      );

      expect(
        container.read(generationControllerProvider).status,
        GenerationStatus.idle,
      );

      final Future<void> generation = container
          .read(generationControllerProvider.notifier)
          .start();
      expect(
        container.read(generationControllerProvider).status,
        GenerationStatus.processing,
      );
      expect(repository.callCount, 1);
      expect(repository.lastFront, same(front));
      expect(repository.lastSide, same(side));
      expect(repository.lastBack, same(back));

      await container.read(generationControllerProvider.notifier).start();
      expect(repository.callCount, 1);

      completion.complete();
      await generation;
      expect(
        container.read(generationControllerProvider).status,
        GenerationStatus.success,
      );

      final PhotoFlowState photos = container.read(photoFlowControllerProvider);
      expect(photos.front, same(front));
      expect(photos.side, same(side));
      expect(photos.back, same(back));
    },
  );

  test('repository failure can retry once and then succeed', () async {
    final _ControlledRepository repository = _ControlledRepository(
      completions: <Future<void>>[
        Future<void>.error(StateError('deterministic failure')),
        Future<void>.value(),
      ],
    );
    final ProviderContainer container = _container(
      repository: repository,
      photoState: PhotoFlowState(
        front: XFile('/photos/front.jpg'),
        side: XFile('/photos/side.jpg'),
        back: XFile('/photos/back.jpg'),
      ),
    );
    final GenerationController controller = container.read(
      generationControllerProvider.notifier,
    );

    await controller.start();
    expect(
      container.read(generationControllerProvider).status,
      GenerationStatus.failure,
    );
    expect(
      container.read(generationControllerProvider).errorMessage,
      '生成过程中出现问题，请重新尝试',
    );
    expect(repository.callCount, 1);

    await controller.retry();
    expect(
      container.read(generationControllerProvider).status,
      GenerationStatus.success,
    );
    expect(repository.callCount, 2);
  });

  test('retry is ignored outside failure state', () async {
    final _ControlledRepository repository = _ControlledRepository(
      completions: <Future<void>>[Future<void>.value()],
    );
    final ProviderContainer container = _container(
      repository: repository,
      photoState: PhotoFlowState(
        front: XFile('/photos/front.jpg'),
        side: XFile('/photos/side.jpg'),
        back: XFile('/photos/back.jpg'),
      ),
    );
    final GenerationController controller = container.read(
      generationControllerProvider.notifier,
    );

    await controller.retry();
    expect(repository.callCount, 0);
    expect(
      container.read(generationControllerProvider).status,
      GenerationStatus.idle,
    );

    await controller.start();
    await controller.retry();
    expect(repository.callCount, 1);
    expect(
      container.read(generationControllerProvider).status,
      GenerationStatus.success,
    );
  });

  test(
    'incomplete photos fail safely without calling the repository',
    () async {
      final XFile front = XFile('/photos/front.jpg');
      final _ControlledRepository repository = _ControlledRepository();
      final ProviderContainer container = _container(
        repository: repository,
        photoState: PhotoFlowState(front: front),
      );

      await container.read(generationControllerProvider.notifier).start();

      final GenerationState generation = container.read(
        generationControllerProvider,
      );
      expect(generation.status, GenerationStatus.failure);
      expect(generation.errorMessage, '照片尚未完整');
      expect(repository.callCount, 0);
      final PhotoFlowState photos = container.read(photoFlowControllerProvider);
      expect(photos.front, same(front));
      expect(photos.side, isNull);
      expect(photos.back, isNull);
    },
  );
}

ProviderContainer _container({
  required DigitalTwinRepository repository,
  required PhotoFlowState photoState,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      digitalTwinRepositoryProvider.overrideWithValue(repository),
      photoFlowControllerProvider.overrideWith(
        () => _SeededPhotoFlowController(photoState),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _SeededPhotoFlowController extends PhotoFlowController {
  _SeededPhotoFlowController(this.initialState);

  final PhotoFlowState initialState;

  @override
  PhotoFlowState build() => initialState;
}

class _ControlledRepository implements DigitalTwinRepository {
  _ControlledRepository({this.completions = const <Future<void>>[]});

  final List<Future<void>> completions;
  int callCount = 0;
  XFile? lastFront;
  XFile? lastSide;
  XFile? lastBack;

  @override
  Future<void> generateDigitalTwin({
    required XFile front,
    required XFile side,
    required XFile back,
  }) {
    lastFront = front;
    lastSide = side;
    lastBack = back;
    final int callIndex = callCount++;
    if (callIndex >= completions.length) {
      return Future<void>.value();
    }
    return completions[callIndex];
  }
}
