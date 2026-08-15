import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:human_twin_ai/app/app.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/generation/generation_controller.dart';
import 'package:image_picker/image_picker.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

void main() {
  testWidgets(
    'Success opens Viewer, returns without regenerating, and reopens safely',
    (WidgetTester tester) async {
      _configureView(tester, const Size(390, 844));
      final Completer<void> completion = Completer<void>();
      final _ControlledRepository repository = _ControlledRepository(
        completions: <Future<void>>[completion.future],
      );
      final _ProcessingTestApp app = await _pumpApp(
        tester,
        repository: repository,
        photoState: _completePhotos(),
      );

      app.router.go('/processing');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('processing-screen')),
        findsOneWidget,
      );
      expect(find.text('正在构建你的数字人体'), findsOneWidget);
      expect(find.text('AI 生成中'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('processing-view-twin-cta')),
        findsNothing,
      );
      expect(repository.callCount, 1);

      tester.view.physicalSize = const Size(389, 844);
      await tester.pump();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(repository.callCount, 1);
      expect(
        find.byKey(const ValueKey<String>('processing-view-twin-cta')),
        findsNothing,
      );

      completion.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('你的数字人体已生成'), findsOneWidget);
      expect(find.text('生成完成'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('processing-view-twin-cta')),
        findsOneWidget,
      );
      expect(find.byType(ModelViewer), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('processing-view-twin-cta')),
      );
      await tester.pumpAndSettle();

      expect(app.router.state.matchedLocation, '/viewer');
      expect(
        find.byKey(const ValueKey<String>('fake-viewer-screen')),
        findsOneWidget,
      );
      expect(find.byType(ModelViewer), findsNothing);
      expect(repository.callCount, 1);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(app.router.state.matchedLocation, '/processing');
      expect(find.text('你的数字人体已生成'), findsOneWidget);
      expect(find.text('生成完成'), findsOneWidget);
      expect(repository.callCount, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('processing-view-twin-cta')),
      );
      await tester.pumpAndSettle();

      expect(app.router.state.matchedLocation, '/viewer');
      expect(
        find.byKey(const ValueKey<String>('fake-viewer-screen')),
        findsOneWidget,
      );
      expect(repository.callCount, 1);
    },
  );

  testWidgets(
    'Failure exposes retry and retry returns to processing then success',
    (WidgetTester tester) async {
      _configureView(tester, const Size(390, 844));
      final Completer<void> retryCompletion = Completer<void>();
      final _ControlledRepository repository = _ControlledRepository(
        completions: <Future<void>>[
          Future<void>.value(),
          retryCompletion.future,
        ],
        failingCalls: const <int>{0},
      );
      final _ProcessingTestApp app = await _pumpApp(
        tester,
        repository: repository,
        photoState: _completePhotos(),
      );

      app.router.go('/processing');
      await tester.pump();
      await tester.pump();

      expect(find.text('生成失败'), findsWidgets);
      expect(find.text('生成过程中出现问题，请重新尝试'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('processing-retry-cta')),
        findsOneWidget,
      );
      expect(repository.callCount, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('processing-retry-cta')),
      );
      await tester.pump();

      expect(find.text('正在构建你的数字人体'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('processing-retry-cta')),
        findsNothing,
      );
      expect(repository.callCount, 2);

      retryCompletion.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('生成完成'), findsOneWidget);
    },
  );

  testWidgets('Direct incomplete Processing entry returns to Photo Selection', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(390, 844));
    final Completer<void> completion = Completer<void>();
    final _ControlledRepository repository = _ControlledRepository(
      completions: <Future<void>>[completion.future],
    );
    final _ProcessingTestApp app = await _pumpApp(
      tester,
      repository: repository,
      photoState: PhotoFlowState(front: XFile('/photos/front.jpg')),
    );

    app.router.go('/processing');
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('processing-incomplete')),
      findsOneWidget,
    );
    expect(find.text('照片尚未完整'), findsOneWidget);
    expect(repository.callCount, 0);
    expect(
      app.container.read(generationControllerProvider).status,
      GenerationStatus.idle,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('processing-incomplete-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.router.state.matchedLocation, '/photos');
    expect(find.text('选择三视图照片'), findsOneWidget);

    final _SeededPhotoFlowController photos =
        app.container.read(photoFlowControllerProvider.notifier)
            as _SeededPhotoFlowController;
    photos.replaceWith(_completePhotos());
    app.router.go('/processing');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('正在构建你的数字人体'), findsOneWidget);
    expect(repository.callCount, 1);
    completion.complete();
    await tester.pump();
  });

  testWidgets('Processing remains usable at 360dp and 200 percent text', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(360, 650), textScaleFactor: 2);
    final _ControlledRepository repository = _ControlledRepository(
      completions: <Future<void>>[Future<void>.value()],
    );
    final _ProcessingTestApp app = await _pumpApp(
      tester,
      repository: repository,
      photoState: _completePhotos(),
    );

    app.router.go('/processing');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('processing-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('processing-view-twin-cta')),
      220,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('processing-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('processing-view-twin-cta')),
      findsOneWidget,
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey<String>('processing-view-twin-cta')),
          )
          .dy,
      lessThanOrEqualTo(650),
    );
    expect(tester.takeException(), isNull);
  });
}

PhotoFlowState _completePhotos() {
  return PhotoFlowState(
    front: XFile('/photos/front.jpg'),
    side: XFile('/photos/side.jpg'),
    back: XFile('/photos/back.jpg'),
  );
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

Future<_ProcessingTestApp> _pumpApp(
  WidgetTester tester, {
  required DigitalTwinRepository repository,
  required PhotoFlowState photoState,
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      digitalTwinRepositoryProvider.overrideWithValue(repository),
      photoFlowControllerProvider.overrideWith(
        () => _SeededPhotoFlowController(photoState),
      ),
    ],
  );
  final GoRouter router = createAppRouter(
    viewerBuilder: (BuildContext context) => const _FakeViewerRoute(),
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: HumanTwinApp(router: router),
    ),
  );
  await tester.pump();
  return _ProcessingTestApp(container: container, router: router);
}

class _ProcessingTestApp {
  const _ProcessingTestApp({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;
}

class _FakeViewerRoute extends StatelessWidget {
  const _FakeViewerRoute();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: ValueKey<String>('fake-viewer-screen'),
      body: Center(child: Text('Viewer test route')),
    );
  }
}

class _SeededPhotoFlowController extends PhotoFlowController {
  _SeededPhotoFlowController(this.initialState);

  final PhotoFlowState initialState;

  @override
  PhotoFlowState build() => initialState;

  void replaceWith(PhotoFlowState nextState) {
    state = nextState;
  }

  @override
  Future<void> retrieveLostData() async {}
}

class _ControlledRepository implements DigitalTwinRepository {
  _ControlledRepository({
    this.completions = const <Future<void>>[],
    this.failingCalls = const <int>{},
  });

  final List<Future<void>> completions;
  final Set<int> failingCalls;
  int callCount = 0;

  @override
  Future<void> generateDigitalTwin({
    required XFile front,
    required XFile side,
    required XFile back,
  }) {
    final int callIndex = callCount++;
    if (failingCalls.contains(callIndex)) {
      return Future<void>.sync(() => throw StateError('controlled failure'));
    }
    if (callIndex >= completions.length) {
      return Future<void>.value();
    }
    return completions[callIndex];
  }
}
