import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('starts with three independent empty slots', () {
    final FakeImagePicker picker = FakeImagePicker();
    final ProviderContainer container = createContainer(picker);

    final PhotoFlowState state = container.read(photoFlowControllerProvider);

    expect(state.front, isNull);
    expect(state.side, isNull);
    expect(state.back, isNull);
    expect(state.isComplete, isFalse);
  });

  test(
    'select keeps front, side, and back independent and completes flow',
    () async {
      final XFile front = XFile('/photos/front.jpg');
      final XFile side = XFile('/photos/side.jpg');
      final XFile back = XFile('/photos/back.jpg');
      final FakeImagePicker picker = FakeImagePicker(
        pickResults: <XFile?>[front, side, back],
      );
      final ProviderContainer container = createContainer(picker);
      final PhotoFlowController controller = container.read(
        photoFlowControllerProvider.notifier,
      );

      await controller.select(PhotoAngle.front, source: ImageSource.gallery);
      expect(container.read(photoFlowControllerProvider).front, same(front));
      expect(container.read(photoFlowControllerProvider).side, isNull);
      expect(container.read(photoFlowControllerProvider).back, isNull);

      await controller.select(PhotoAngle.side, source: ImageSource.camera);
      await controller.select(PhotoAngle.back, source: ImageSource.gallery);

      final PhotoFlowState state = container.read(photoFlowControllerProvider);
      expect(state.front, same(front));
      expect(state.side, same(side));
      expect(state.back, same(back));
      expect(state.isComplete, isTrue);
      expect(controller.isComplete, isTrue);
      expect(picker.sources, <ImageSource>[
        ImageSource.gallery,
        ImageSource.camera,
        ImageSource.gallery,
      ]);
    },
  );

  test('replace changes only the requested slot', () async {
    final XFile original = XFile('/photos/front-original.jpg');
    final XFile replacement = XFile('/photos/front-replacement.jpg');
    final XFile side = XFile('/photos/side.jpg');
    final FakeImagePicker picker = FakeImagePicker(
      pickResults: <XFile?>[original, side, replacement],
    );
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );

    await controller.select(PhotoAngle.front, source: ImageSource.gallery);
    await controller.select(PhotoAngle.side, source: ImageSource.gallery);
    await controller.replace(PhotoAngle.front, source: ImageSource.camera);

    final PhotoFlowState state = container.read(photoFlowControllerProvider);
    expect(state.front, same(replacement));
    expect(state.side, same(side));
    expect(state.back, isNull);
  });

  test('cancel preserves an existing photo and the prior flow state', () async {
    final XFile original = XFile('/photos/front.jpg');
    final FakeImagePicker picker = FakeImagePicker(
      pickResults: <XFile?>[original, null],
    );
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );

    await controller.select(PhotoAngle.front, source: ImageSource.gallery);
    final PhotoFlowState beforeCancel = container.read(
      photoFlowControllerProvider,
    );
    await controller.replace(PhotoAngle.front, source: ImageSource.camera);

    final PhotoFlowState afterCancel = container.read(
      photoFlowControllerProvider,
    );
    expect(afterCancel.front, same(original));
    expect(afterCancel.side, same(beforeCancel.side));
    expect(afterCancel.back, same(beforeCancel.back));
    expect(afterCancel.pendingAngle, same(beforeCancel.pendingAngle));
    expect(afterCancel.errorMessage, same(beforeCancel.errorMessage));
  });

  test('remove disables completion and reset clears every slot', () async {
    final FakeImagePicker picker = FakeImagePicker(
      pickResults: <XFile?>[
        XFile('/photos/front.jpg'),
        XFile('/photos/side.jpg'),
        XFile('/photos/back.jpg'),
      ],
    );
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );

    for (final PhotoAngle angle in PhotoAngle.values) {
      await controller.select(angle, source: ImageSource.gallery);
    }
    expect(controller.isComplete, isTrue);

    controller.remove(PhotoAngle.side);
    expect(container.read(photoFlowControllerProvider).side, isNull);
    expect(controller.isComplete, isFalse);

    controller.reset();
    final PhotoFlowState resetState = container.read(
      photoFlowControllerProvider,
    );
    expect(resetState.front, isNull);
    expect(resetState.side, isNull);
    expect(resetState.back, isNull);
    expect(resetState.isComplete, isFalse);
  });

  test('remove clears a pending picker and ignores its stale result', () async {
    final Completer<XFile?> pendingPick = Completer<XFile?>();
    final FakeImagePicker picker = FakeImagePicker(pendingPick: pendingPick);
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );

    final Future<void> pickFuture = controller.select(
      PhotoAngle.front,
      source: ImageSource.gallery,
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(photoFlowControllerProvider).isPicking, isTrue);

    controller.remove(PhotoAngle.side);
    expect(container.read(photoFlowControllerProvider).isPicking, isFalse);

    pendingPick.complete(XFile('/photos/stale-front.jpg'));
    await pickFuture;
    final PhotoFlowState state = container.read(photoFlowControllerProvider);
    expect(state.front, isNull);
    expect(state.side, isNull);
    expect(state.back, isNull);
  });

  test('empty lost-data response leaves current state unchanged', () async {
    final XFile front = XFile('/photos/front.jpg');
    final FakeImagePicker picker = FakeImagePicker(
      pickResults: <XFile?>[front],
      lostDataResponse: LostDataResponse.empty(),
    );
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );
    await controller.select(PhotoAngle.front, source: ImageSource.gallery);
    final PhotoFlowState beforeRecovery = container.read(
      photoFlowControllerProvider,
    );

    await controller.retrieveLostData();

    expect(container.read(photoFlowControllerProvider), same(beforeRecovery));
    expect(picker.retrieveLostDataCallCount, 1);
  });

  test(
    'lost data recovers into the pending slot without stale cancel rollback',
    () async {
      final XFile recovered = XFile('/photos/recovered-side.jpg');
      final Completer<XFile?> pendingPick = Completer<XFile?>();
      final FakeImagePicker picker = FakeImagePicker(
        pendingPick: pendingPick,
        lostDataResponse: LostDataResponse(
          file: recovered,
          files: <XFile>[recovered],
          type: RetrieveType.image,
        ),
      );
      final ProviderContainer container = createContainer(picker);
      final PhotoFlowController controller = container.read(
        photoFlowControllerProvider.notifier,
      );

      final Future<void> pickFuture = controller.select(
        PhotoAngle.side,
        source: ImageSource.gallery,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(photoFlowControllerProvider).pendingAngle,
        PhotoAngle.side,
      );

      await controller.retrieveLostData();
      pendingPick.complete(null);
      await pickFuture;

      final PhotoFlowState state = container.read(photoFlowControllerProvider);
      expect(state.front, isNull);
      expect(state.side, same(recovered));
      expect(state.back, isNull);
      expect(state.pendingAngle, isNull);
    },
  );

  test('lost data falls back to the first empty slot after relaunch', () async {
    final XFile recovered = XFile('/photos/recovered-front.jpg');
    final FakeImagePicker picker = FakeImagePicker(
      lostDataResponse: LostDataResponse(
        file: recovered,
        files: <XFile>[recovered],
        type: RetrieveType.image,
      ),
    );
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );

    await controller.retrieveLostData();

    final PhotoFlowState state = container.read(photoFlowControllerProvider);
    expect(state.front, same(recovered));
    expect(state.side, isNull);
    expect(state.back, isNull);
  });

  test('a stale lost-data response cannot overwrite a newer pick', () async {
    final XFile stale = XFile('/photos/stale-front.jpg');
    final XFile fresh = XFile('/photos/fresh-front.jpg');
    final Completer<LostDataResponse> pendingRecovery =
        Completer<LostDataResponse>();
    final Completer<XFile?> pendingPick = Completer<XFile?>();
    final FakeImagePicker picker = FakeImagePicker(
      pendingPick: pendingPick,
      pendingLostData: pendingRecovery,
    );
    final ProviderContainer container = createContainer(picker);
    final PhotoFlowController controller = container.read(
      photoFlowControllerProvider.notifier,
    );

    final Future<void> recovery = controller.retrieveLostData();
    await Future<void>.delayed(Duration.zero);
    final Future<void> pick = controller.select(
      PhotoAngle.front,
      source: ImageSource.gallery,
    );
    pendingRecovery.complete(
      LostDataResponse(
        file: stale,
        files: <XFile>[stale],
        type: RetrieveType.image,
      ),
    );
    await recovery;
    pendingPick.complete(fresh);
    await pick;

    final PhotoFlowState state = container.read(photoFlowControllerProvider);
    expect(state.front, same(fresh));
    expect(state.pendingAngle, isNull);
  });
}

ProviderContainer createContainer(FakeImagePicker picker) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      imagePickerProvider.overrideWithValue(picker),
      lostDataRecoverySupportedProvider.overrideWithValue(true),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class FakeImagePicker extends ImagePicker {
  FakeImagePicker({
    List<XFile?> pickResults = const <XFile?>[],
    this.pendingPick,
    this.pendingLostData,
    LostDataResponse? lostDataResponse,
  }) : _pickResults = Queue<XFile?>.of(pickResults),
       lostDataResponse = lostDataResponse ?? LostDataResponse.empty();

  final Queue<XFile?> _pickResults;
  final Completer<XFile?>? pendingPick;
  final Completer<LostDataResponse>? pendingLostData;
  LostDataResponse lostDataResponse;
  final List<ImageSource> sources = <ImageSource>[];
  int retrieveLostDataCallCount = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    sources.add(source);
    if (pendingPick != null) {
      return pendingPick!.future;
    }
    return _pickResults.removeFirst();
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveLostDataCallCount++;
    if (pendingLostData != null) {
      return pendingLostData!.future;
    }
    return lostDataResponse;
  }
}
