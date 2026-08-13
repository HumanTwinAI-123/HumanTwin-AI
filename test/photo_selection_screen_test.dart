import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:human_twin_ai/app/app.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/shared/widgets/photo_slot.dart';
import 'package:human_twin_ai/shared/widgets/primary_button.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  testWidgets(
    'three real slot states enable CTA, survive back, replace, cancel, and remove',
    (WidgetTester tester) async {
      _configureView(tester, const Size(390, 844));
      final XFile front = _testImage('front.png');
      final XFile side = _testImage('side.png');
      final XFile back = _testImage('back.png');
      final XFile replacement = _testImage('front-replacement.png');
      final FakeImagePicker picker = FakeImagePicker(
        pickResults: <Object?>[
          front,
          side,
          back,
          null,
          replacement,
          StateError('replace failed'),
        ],
      );
      final _TestApp testApp = await _pumpTestApp(tester, picker);

      expect(
        picker.retrieveLostDataCallCount,
        1,
        reason: 'the app root must check lost data on cold startup',
      );

      await _openSelection(tester);

      expect(picker.retrieveLostDataCallCount, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        picker.retrieveLostDataCallCount,
        3,
        reason: 'resuming Photo Selection must recheck Android lost data',
      );

      expect(find.byType(PhotoSlot), findsNWidgets(3));
      for (final PhotoAngle angle in PhotoAngle.values) {
        final PhotoSlot slot = tester.widget<PhotoSlot>(
          find.byKey(ValueKey<String>('photo-slot-${angle.name}')),
        );
        expect(slot.state, PhotoSlotState.empty);
        expect(slot.image, isNull);
      }
      expect(
        tester
            .widget<PrimaryButton>(
              find.byKey(const ValueKey<String>('photo-selection-cta')),
            )
            .onPressed,
        isNull,
      );

      await _pickFrom(tester, PhotoAngle.front, action: 'gallery');
      PhotoFlowState state = testApp.container.read(
        photoFlowControllerProvider,
      );
      expect(state.front, same(front));
      expect(state.side, isNull);
      expect(state.back, isNull);

      await _pickFrom(tester, PhotoAngle.side, action: 'camera');
      await _pickFrom(tester, PhotoAngle.back, action: 'gallery');

      state = testApp.container.read(photoFlowControllerProvider);
      expect(state.front, same(front));
      expect(state.side, same(side));
      expect(state.back, same(back));
      expect(state.isComplete, isTrue);
      expect(
        tester
            .widget<PrimaryButton>(
              find.byKey(const ValueKey<String>('photo-selection-cta')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('photo-selection-back')),
      );
      await tester.pumpAndSettle();
      expect(find.text('拍摄说明'), findsOneWidget);
      await tester.tap(find.text('我已了解'));
      await tester.pumpAndSettle();
      expect(find.text('选择三视图照片'), findsOneWidget);
      expect(
        testApp.container.read(photoFlowControllerProvider).isComplete,
        isTrue,
        reason: 'returning through Photo Guide must preserve all three photos',
      );

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('photo-confirmation-card-front')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('photo-confirmation-card-side')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('photo-confirmation-card-back')),
        findsOneWidget,
      );
      expect(find.text('确认三视图照片'), findsOneWidget);
      expect(find.text('DAY 5 · PLACEHOLDER'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('photo-confirmation-back')),
      );
      await tester.pumpAndSettle();
      expect(
        testApp.container.read(photoFlowControllerProvider).isComplete,
        isTrue,
      );

      await _openSlotSheet(tester, PhotoAngle.front);
      await tester.tap(
        find.byKey(const ValueKey<String>('photo-action-cancel')),
      );
      await tester.pumpAndSettle();
      expect(
        testApp.container.read(photoFlowControllerProvider).front,
        same(front),
      );

      await _pickFrom(tester, PhotoAngle.front, action: 'gallery');
      expect(
        testApp.container.read(photoFlowControllerProvider).front,
        same(front),
        reason: 'system picker cancel must preserve the previous photo',
      );

      await _pickFrom(tester, PhotoAngle.front, action: 'gallery');
      state = testApp.container.read(photoFlowControllerProvider);
      expect(state.front, same(replacement));
      expect(state.side, same(side));
      expect(state.back, same(back));

      await _pickFrom(tester, PhotoAngle.front, action: 'gallery');
      state = testApp.container.read(photoFlowControllerProvider);
      expect(state.front, same(replacement));
      expect(state.errorFor(PhotoAngle.front), isNotNull);
      expect(
        tester
            .widget<PhotoSlot>(
              find.byKey(const ValueKey<String>('photo-slot-front')),
            )
            .state,
        PhotoSlotState.filled,
        reason: 'a failed replace keeps the still-valid previous photo',
      );
      expect(
        tester
            .widget<PrimaryButton>(
              find.byKey(const ValueKey<String>('photo-selection-cta')),
            )
            .onPressed,
        isNotNull,
      );

      await _openSlotSheet(tester, PhotoAngle.side);
      await tester.tap(
        find.byKey(const ValueKey<String>('photo-action-remove')),
      );
      await tester.pumpAndSettle();

      state = testApp.container.read(photoFlowControllerProvider);
      expect(state.front, same(replacement));
      expect(state.side, isNull);
      expect(state.back, same(back));
      expect(state.isComplete, isFalse);
      expect(
        tester
            .widget<PrimaryButton>(
              find.byKey(const ValueKey<String>('photo-selection-cta')),
            )
            .onPressed,
        isNull,
      );
      expect(picker.sources, <ImageSource>[
        ImageSource.gallery,
        ImageSource.camera,
        ImageSource.gallery,
        ImageSource.gallery,
        ImageSource.gallery,
        ImageSource.gallery,
      ]);
      expect(picker.retrieveLostDataCallCount, 4);
    },
  );

  testWidgets('Photo Selection remains scrollable at 360dp and 200% text', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(360, 650), textScaleFactor: 2);
    final FakeImagePicker picker = FakeImagePicker();
    await _pumpTestApp(tester, picker);

    await _openSelection(tester);

    expect(
      find.byKey(const ValueKey<String>('photo-selection-scroll')),
      findsOneWidget,
    );
    expect(find.byType(PhotoSlot), findsNWidgets(3));
    expect(find.text('03 / 06'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('稍后'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('photo-selection-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('稍后'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey<String>('photo-selection-cta')),
          )
          .dy,
      lessThanOrEqualTo(650),
    );
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

Future<_TestApp> _pumpTestApp(
  WidgetTester tester,
  FakeImagePicker picker,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      imagePickerProvider.overrideWithValue(picker),
      lostDataRecoverySupportedProvider.overrideWithValue(true),
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
  return _TestApp(container: container);
}

Future<void> _openSelection(WidgetTester tester) async {
  await tester.ensureVisible(find.text('开始创建'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始创建'));
  await tester.pumpAndSettle();
  expect(find.text('拍摄说明'), findsOneWidget);

  await tester.tap(find.text('我已了解'));
  await tester.pumpAndSettle();
  expect(find.text('选择三视图照片'), findsOneWidget);
}

Future<void> _openSlotSheet(WidgetTester tester, PhotoAngle angle) async {
  await tester.tap(find.byKey(ValueKey<String>('photo-slot-${angle.name}')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('photo-action-gallery')),
    findsOneWidget,
  );
}

Future<void> _pickFrom(
  WidgetTester tester,
  PhotoAngle angle, {
  required String action,
}) async {
  await _openSlotSheet(tester, angle);
  await tester.tap(find.byKey(ValueKey<String>('photo-action-$action')));
  await tester.pumpAndSettle();
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

class _TestApp {
  const _TestApp({required this.container});

  final ProviderContainer container;
}

class FakeImagePicker extends ImagePicker {
  FakeImagePicker({List<Object?> pickResults = const <Object?>[]})
    : _pickResults = Queue<Object?>.of(pickResults);

  final Queue<Object?> _pickResults;
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
    if (_pickResults.isEmpty) {
      return null;
    }
    final Object? result = _pickResults.removeFirst();
    if (result == null || result is XFile) {
      return result as XFile?;
    }
    throw result;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveLostDataCallCount++;
    return LostDataResponse.empty();
  }
}
