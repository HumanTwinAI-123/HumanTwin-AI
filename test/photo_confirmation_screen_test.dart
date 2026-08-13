import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:human_twin_ai/app/app.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  testWidgets(
    'Confirmation maps controller photos, preserves state, and reflects one replacement',
    (WidgetTester tester) async {
      _configureView(tester, const Size(390, 844));
      final XFile front = _testImage('front.png');
      final XFile side = _testImage('side.png');
      final XFile back = _testImage('back.png');
      final XFile replacement = _testImage('front-updated.png');
      final FakeConfirmationImagePicker picker = FakeConfirmationImagePicker(
        pickResults: <XFile>[front, side, back, replacement],
      );
      final _ConfirmationTestApp app = await _pumpConfirmationApp(
        tester,
        picker,
      );
      final PhotoFlowController controller = app.container.read(
        photoFlowControllerProvider.notifier,
      );

      await controller.select(PhotoAngle.front, source: ImageSource.gallery);
      await controller.select(PhotoAngle.side, source: ImageSource.gallery);
      await controller.select(PhotoAngle.back, source: ImageSource.gallery);
      app.router.go('/photos');
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('photo-selection-cta')),
      );
      await tester.pumpAndSettle();

      expect(find.text('照片确认'), findsOneWidget);
      expect(find.text('04 / 06'), findsOneWidget);
      expect(find.text('正面照片'), findsOneWidget);
      expect(find.text('侧面照片'), findsOneWidget);
      expect(find.text('背面照片'), findsOneWidget);
      _expectMappedImage(PhotoAngle.front, front);
      _expectMappedImage(PhotoAngle.side, side);
      _expectMappedImage(PhotoAngle.back, back);
      _expectCardMapping(PhotoAngle.front, 'FRONT');
      _expectCardMapping(PhotoAngle.side, 'SIDE');
      _expectCardMapping(PhotoAngle.back, 'BACK');

      PhotoFlowState state = app.container.read(photoFlowControllerProvider);
      expect(state.front, same(front));
      expect(state.side, same(side));
      expect(state.back, same(back));

      await tester.tap(
        find.byKey(const ValueKey<String>('photo-confirmation-edit-front')),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择三视图照片'), findsOneWidget);
      state = app.container.read(photoFlowControllerProvider);
      expect(state.front, same(front));
      expect(state.side, same(side));
      expect(state.back, same(back));

      await tester.tap(find.byKey(const ValueKey<String>('photo-slot-front')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('photo-action-gallery')),
      );
      await tester.pumpAndSettle();

      state = app.container.read(photoFlowControllerProvider);
      expect(state.front, same(replacement));
      expect(state.side, same(side));
      expect(state.back, same(back));

      await tester.tap(
        find.byKey(const ValueKey<String>('photo-selection-cta')),
      );
      await tester.pumpAndSettle();

      _expectMappedImage(PhotoAngle.front, replacement);
      _expectMappedImage(PhotoAngle.side, side);
      _expectMappedImage(PhotoAngle.back, back);
      expect(find.byKey(_imageKey(PhotoAngle.front, front)), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('photo-confirmation-cta')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('processing-screen')),
        findsOneWidget,
      );
      expect(find.text('你的数字人体已生成'), findsOneWidget);
      expect(find.text('生成完成'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('processing-view-twin-cta')),
        findsOneWidget,
      );
      expect(picker.sources, <ImageSource>[
        ImageSource.gallery,
        ImageSource.gallery,
        ImageSource.gallery,
        ImageSource.gallery,
      ]);
    },
  );

  testWidgets('incomplete Confirmation blocks generation and returns safely', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(390, 844));
    final XFile front = _testImage('front-only.png');
    final FakeConfirmationImagePicker picker = FakeConfirmationImagePicker(
      pickResults: <XFile>[front],
    );
    final _ConfirmationTestApp app = await _pumpConfirmationApp(tester, picker);
    await app.container
        .read(photoFlowControllerProvider.notifier)
        .select(PhotoAngle.front, source: ImageSource.gallery);

    app.router.go('/photo-confirmation');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('photo-confirmation-incomplete')),
      findsOneWidget,
    );
    expect(find.text('照片尚未完整'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('photo-confirmation-cta')),
      findsNothing,
    );
    expect(find.text('开始生成'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('photo-confirmation-incomplete-action'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择三视图照片'), findsOneWidget);
    final PhotoFlowState state = app.container.read(
      photoFlowControllerProvider,
    );
    expect(state.front, same(front));
    expect(state.side, isNull);
    expect(state.back, isNull);
  });

  testWidgets(
    'direct incomplete Processing route returns safely to Selection',
    (WidgetTester tester) async {
      _configureView(tester, const Size(390, 844));
      final _ConfirmationTestApp app = await _pumpConfirmationApp(
        tester,
        FakeConfirmationImagePicker(),
      );

      app.router.go('/processing');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('processing-incomplete-action')),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择三视图照片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Confirmation stays scrollable at 360dp and 200% text', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(360, 650), textScaleFactor: 2);
    final FakeConfirmationImagePicker picker = FakeConfirmationImagePicker(
      pickResults: <XFile>[
        _testImage('front-small.png'),
        _testImage('side-small.png'),
        _testImage('back-small.png'),
      ],
    );
    final _ConfirmationTestApp app = await _pumpConfirmationApp(tester, picker);
    final PhotoFlowController controller = app.container.read(
      photoFlowControllerProvider.notifier,
    );
    for (final PhotoAngle angle in PhotoAngle.values) {
      await controller.select(angle, source: ImageSource.gallery);
    }
    app.router.go('/photos');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('photo-selection-cta')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('photo-confirmation-scroll')),
      findsOneWidget,
    );
    expect(find.text('04 / 06'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey<String>('photo-confirmation-cta')),
          )
          .dy,
      lessThanOrEqualTo(650),
    );

    await tester.scrollUntilVisible(
      find.text('稍后'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('photo-confirmation-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('稍后'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('photo-confirmation-card-back')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

void _configureView(
  WidgetTester tester,
  Size size, {
  double textScaleFactor = 1,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<_ConfirmationTestApp> _pumpConfirmationApp(
  WidgetTester tester,
  FakeConfirmationImagePicker picker,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      imagePickerProvider.overrideWithValue(picker),
      lostDataRecoverySupportedProvider.overrideWithValue(false),
      digitalTwinRepositoryProvider.overrideWithValue(
        MockDigitalTwinRepository(delay: Duration.zero),
      ),
    ],
  );
  final GoRouter router = createAppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: HumanTwinApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
  return _ConfirmationTestApp(container: container, router: router);
}

void _expectMappedImage(PhotoAngle angle, XFile image) {
  expect(find.byKey(_imageKey(angle, image)), findsOneWidget);
}

void _expectCardMapping(PhotoAngle angle, String englishLabel) {
  final Finder card = find.byKey(
    ValueKey<String>('photo-confirmation-card-${angle.name}'),
  );
  expect(
    find.descendant(of: card, matching: find.textContaining(englishLabel)),
    findsOneWidget,
  );
}

ValueKey<String> _imageKey(PhotoAngle angle, XFile image) {
  return ValueKey<String>(
    'photo-confirmation-image-${angle.name}-${image.path}',
  );
}

XFile _testImage(String path) {
  final Uint8List bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  return XFile.fromData(
    bytes,
    path: '/tmp/$path',
    name: path,
    mimeType: 'image/png',
  );
}

class _ConfirmationTestApp {
  const _ConfirmationTestApp({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;
}

class FakeConfirmationImagePicker extends ImagePicker {
  FakeConfirmationImagePicker({List<XFile> pickResults = const <XFile>[]})
    : _pickResults = Queue<XFile>.of(pickResults);

  final Queue<XFile> _pickResults;
  final List<ImageSource> sources = <ImageSource>[];

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
    return _pickResults.removeFirst();
  }
}
