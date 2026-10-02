import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:human_twin_ai/app/theme/app_theme.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/library/avatar_detail_screen.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/library/library_controller.dart';
import 'package:human_twin_ai/features/viewer/digital_twin_viewer.dart';
import 'package:human_twin_ai/shared/storage/local_store.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'support/harness.dart';

void main() {
  test(
    'Production viewer registers one lifecycle channel and its DOM bridge',
    () {
      final ModelViewer viewer = buildHumanModelViewer();

      expect(viewer.debugLogging, isFalse);
      expect(viewer.javascriptChannels, hasLength(1));
      expect(
        viewer.javascriptChannels!.single.name,
        'HumanTwinViewerLifecycle',
      );
      expect(
        viewer.relatedJs,
        allOf(
          contains("document.querySelector('model-viewer')"),
          contains("window.addEventListener('load'"),
          contains(RegExp(r"modelViewer\.addEventListener\(\s*'load'")),
          contains(RegExp(r"modelViewer\.addEventListener\(\s*'error'")),
          contains("send('page-ready')"),
          contains("send('model-loaded')"),
          contains("send('model-error')"),
        ),
      );
    },
  );

  test('Production viewer loads the given model and describes its origin', () {
    final ModelViewer sample = buildHumanModelViewer();
    final ModelViewer generated = buildHumanModelViewer(model: _generatedModel);

    expect(sample.src, sampleModelAsset);
    expect(sample.alt, contains('示例'));
    expect(generated.src, _generatedModel.src);
    expect(generated.alt, isNot(sample.alt));
  });

  test('Debug timings accept only finite numbers and known stages', () {
    expect(viewerLoadTimingFromMessage('timing:model-resource:125.5'), (
      stage: 'model-resource',
      pageElapsedMs: 125.5,
    ));
    expect(viewerLoadTimingFromMessage('timing:two-raf:250'), (
      stage: 'two-raf',
      pageElapsedMs: 250.0,
    ));
    for (final String message in <String>[
      'timing:unknown:10',
      'timing:model-resource:NaN',
      'timing:model-resource:Infinity',
      'timing:model-resource:-1',
      'timing:model-resource:https://example.invalid/private.glb',
      'timing:two-raf:/private/model.glb',
    ]) {
      expect(viewerLoadTimingFromMessage(message), isNull);
    }
  });

  testWidgets(
    'System back stays on the detail page while the viewer is unsafe',
    (WidgetTester tester) async {
      final _Harness harness = await _pumpDetail(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byType(AvatarDetailScreen), findsOneWidget);
      expect(harness.observer.detailPops, 0);
    },
  );

  testWidgets('A pending back returns once when page-ready arrives', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpDetail(tester);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    expect(find.byType(AvatarDetailScreen), findsOneWidget);
    expect(harness.observer.detailPops, 0);

    harness.driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(harness.observer.detailPops, 1);
  });

  for (final ViewerLifecycleEvent event in <ViewerLifecycleEvent>[
    ViewerLifecycleEvent.modelLoaded,
    ViewerLifecycleEvent.modelError,
  ]) {
    testWidgets('A pending exit returns once when ${event.name} arrives', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpDetail(tester);

      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      harness.driver.send(event);
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(harness.observer.detailPops, 1);
    });
  }

  testWidgets('Repeated and mixed early back requests produce one pop', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpDetail(tester);

    await tester.tap(find.byTooltip('返回'));
    await tester.tap(find.byTooltip('返回'));
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(harness.observer.detailPops, 0);

    harness.driver
      ..send(ViewerLifecycleEvent.pageReady)
      ..send(ViewerLifecycleEvent.modelLoaded)
      ..send(ViewerLifecycleEvent.modelError);
    await tester.pumpAndSettle();

    expect(harness.observer.detailPops, 1);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Ready before back allows immediate UI and system returns', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpDetail(tester);

    harness.driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pump();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(harness.observer.detailPops, 1);

    await _open(tester, harness);
    harness.driver.send(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(harness.observer.detailPops, 2);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('A watchdog timeout alone does not unlock exit', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpDetail(
      tester,
      driver: ViewerDriver(probeResult: false),
      watchdog: const Duration(milliseconds: 100),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(harness.driver.probeCalls, 1);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    expect(find.byType(AvatarDetailScreen), findsOneWidget);
    expect(harness.observer.detailPops, 0);
  });

  testWidgets('A positive watchdog probe releases one pending exit', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpDetail(
      tester,
      driver: ViewerDriver(probeResult: true),
      watchdog: const Duration(milliseconds: 100),
    );

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(harness.driver.probeCalls, 1);
    expect(harness.observer.detailPops, 1);
  });

  testWidgets('Reload ignores a double tap and keeps exit safe', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final Completer<void> reloadDone = Completer<void>();
    final _Harness harness = await _pumpDetail(
      tester,
      driver: ViewerDriver(reloadAction: () => reloadDone.future),
    );
    harness.driver.send(ViewerLifecycleEvent.modelError);
    await tester.pump();
    expect(find.text('3D 模型加载失败'), findsOneWidget);

    final Finder reload = find.byKey(const ValueKey<String>('viewer-reload'));
    // Two taps in the same frame: the second one hits the in-flight guard.
    await tester.tap(reload);
    await tester.tap(reload);
    await tester.pump();
    expect(reload, findsNothing);
    expect(harness.driver.reloadCalls, 1);

    reloadDone.complete();
    await tester.pump();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(harness.observer.detailPops, 1);
  });

  testWidgets('A stale lifecycle callback is ignored after reopening', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpDetail(tester);
    final ValueChanged<ViewerLifecycleEvent> stale =
        harness.driver.lifecycleCallback!;
    harness.driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pump();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    await _open(tester, harness);
    stale(ViewerLifecycleEvent.modelError);
    await tester.pump();
    expect(find.byType(AvatarDetailScreen), findsOneWidget);
    expect(find.text('3D 模型加载失败'), findsNothing);
    expect(harness.observer.detailPops, 1);

    harness.driver.send(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(harness.observer.detailPops, 2);
  });

  testWidgets('An ordinary rebuild keeps one viewer host', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    await _pumpDetail(tester);
    final State<StatefulWidget> before = tester.state(find.byType(FakeViewer));

    tester.view.physicalSize = const Size(389, 844);
    await tester.pump();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();

    expect(tester.state(find.byType(FakeViewer)), same(before));
    expect(find.byKey(const ValueKey<String>('viewer-host')), findsOneWidget);
  });

  testWidgets(
    'A replacement host ignores old lifecycle events and an in-flight probe',
    (WidgetTester tester) async {
      configureView(tester, const Size(390, 844));
      final _HostRecorder hosts = _HostRecorder();
      final _Harness harness = await _pumpDetail(
        tester,
        viewerBuilder: hosts.build,
        watchdog: const Duration(milliseconds: 100),
      );
      final _HostCallbacks old = hosts.calls.last;
      final Completer<bool> oldProbe = Completer<bool>();
      old.registerProbe(() => oldProbe.future);
      await tester.pump(const Duration(milliseconds: 100));
      old.onLifecycle(ViewerLifecycleEvent.modelError);
      await tester.pump();
      // No controller was registered: Reload deliberately creates a new host.
      await tester.tap(find.byKey(const ValueKey<String>('viewer-reload')));
      await tester.pump();
      final _HostCallbacks current = hosts.calls.last;

      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      old.onLifecycle(ViewerLifecycleEvent.pageReady);
      old.onLifecycle(ViewerLifecycleEvent.modelLoaded);
      old.onLifecycle(ViewerLifecycleEvent.modelError);
      oldProbe.complete(true);
      await tester.pump();
      expect(find.byType(AvatarDetailScreen), findsOneWidget);
      expect(find.text('正在加载 3D 模型…'), findsOneWidget);
      expect(find.text('3D 模型加载失败'), findsNothing);
      expect(harness.observer.detailPops, 0);

      current.onLifecycle(ViewerLifecycleEvent.pageReady);
      await tester.pumpAndSettle();
      expect(harness.observer.detailPops, 1);
    },
  );

  testWidgets('Old host registrations cannot replace the new reload or probe', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final _HostRecorder hosts = _HostRecorder();
    final _Harness harness = await _pumpDetail(
      tester,
      viewerBuilder: hosts.build,
      watchdog: const Duration(milliseconds: 100),
    );
    final _HostCallbacks old = hosts.calls.last;
    old.onLifecycle(ViewerLifecycleEvent.modelError);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('viewer-reload')));
    await tester.pump();
    final _HostCallbacks current = hosts.calls.last;
    int oldReloads = 0;
    int currentReloads = 0;
    int oldProbes = 0;
    int currentProbes = 0;
    current.registerReload(() async {
      currentReloads++;
    });
    current.registerProbe(() async {
      currentProbes++;
      return false;
    });
    old.registerReload(() async {
      oldReloads++;
    });
    old.registerProbe(() async {
      oldProbes++;
      return true;
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(currentProbes, 1);
    expect(oldProbes, 0);

    current.onLifecycle(ViewerLifecycleEvent.modelError);
    await tester.pump();
    final Finder reload = find.byKey(const ValueKey<String>('viewer-reload'));
    await tester.tap(reload);
    await tester.pump();
    expect(currentReloads, 1);
    expect(oldReloads, 0);
    current.onLifecycle(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(harness.observer.detailPops, 1);
  });

  testWidgets('The sample is labelled as a sample, never as the user', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    expect(find.text('内置示例模型'), findsOneWidget);
    expect(find.text('示例模型'), findsWidgets);
    expect(find.text('创建我的形象'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
  });

  testWidgets('A service result is labelled AI 生成 with its limits', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      recordId: 'rsvc',
      records: <GenerationRecord>[
        doneRecord('rsvc', name: '我的形象', mode: GenerationMode.service),
      ],
    );

    expect(find.text('AI 生成 · 仅供展示'), findsOneWidget);
    expect(find.textContaining('不代表精确的身体数据'), findsOneWidget);
    expect(find.text('内置示例模型'), findsNothing);
  });

  testWidgets('The detail page fits 360 dp at 200% text', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(360, 640), textScale: 2);
    final _Harness harness = await _pumpDetail(
      tester,
      recordId: 'rdemo',
      records: <GenerationRecord>[doneRecord('rdemo')],
    );
    harness.driver.send(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();
    expectNoLayoutErrors(tester, 'detail');

    await tester.scrollUntilVisible(
      find.text('删除这个形象'),
      200,
      scrollable: scrollableIn(AvatarDetailScreen),
    );
    await tester.pump();
    expect(find.text('分享或导出'), findsOneWidget);
    expectNoLayoutErrors(tester, 'detail scrolled');
  });

  testWidgets(
    'A short 200% error overlay scrolls to its working reload action',
    (WidgetTester tester) async {
      configureView(tester, const Size(360, 640), textScale: 2);
      final _Harness harness = await _pumpDetail(tester);
      final double canvasHeight = tester
          .getSize(find.byKey(const ValueKey<String>('viewer-canvas')))
          .height;
      harness.driver.send(ViewerLifecycleEvent.modelError);
      await tester.pump();
      expectNoLayoutErrors(tester, 'short large-text error');
      expect(find.byTooltip('重置视角'), findsNothing);
      expect(find.byTooltip('停止自动旋转'), findsNothing);
      final Finder overlayScrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('viewer-state-scroll')),
        matching: find.byType(Scrollable),
      );
      final ScrollableState overlay = tester.state<ScrollableState>(
        overlayScrollable,
      );
      expect(overlay.position.maxScrollExtent, greaterThan(0));
      final Finder reload = find.byKey(const ValueKey<String>('viewer-reload'));
      await tester.ensureVisible(reload);
      await tester.pump();
      expect(reload.hitTestable(), findsOneWidget);
      expect(overlay.position.pixels, greaterThan(0));
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('viewer-canvas')))
            .height,
        canvasHeight,
      );
      await tester.tap(reload);
      await tester.pump();
      expect(harness.driver.reloadCalls, 1);
      expectNoLayoutErrors(tester, 'short large-text error after reload');
    },
  );

  testWidgets('A short 200% missing-file overlay keeps recovery accessible', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(360, 640), textScale: 2);
    await _pumpDetail(
      tester,
      recordId: 'rmissing',
      records: <GenerationRecord>[
        doneRecord(
          'rmissing',
        ).copyWith(model: const ModelRef.file('records/rmissing/missing.glb')),
      ],
      validateStoredModels: true,
    );
    expect(find.text('本机模型文件已丢失'), findsOneWidget);
    expectNoLayoutErrors(tester, 'short large-text missing file');
    final Finder scroll = find.byKey(
      const ValueKey<String>('viewer-state-scroll'),
    );
    final Finder overlayScrollable = find.descendant(
      of: scroll,
      matching: find.byType(Scrollable),
    );
    final ScrollableState overlay = tester.state<ScrollableState>(
      overlayScrollable,
    );
    expect(overlay.position.maxScrollExtent, greaterThan(0));
    await tester.ensureVisible(
      find.descendant(of: scroll, matching: find.byType(Text)).last,
    );
    await tester.pump();
    expect(overlay.position.pixels, greaterThan(0));
    // Recovery remains the existing fixed bottom action; the explanation scrolls.
    expect(find.text('重新下载').hitTestable(), findsOneWidget);
    expectNoLayoutErrors(tester, 'short large-text missing file scrolled');
  });
}

const DigitalTwinModel _generatedModel = DigitalTwinModel(
  src: 'file:///data/user/0/app/files/humantwin/records/r1/model.glb',
  origin: ModelOrigin.serviceGenerated,
);

class _Harness {
  _Harness(this.observer, this.driver, this.router, this.recordId);

  final _DetailObserver observer;
  final ViewerDriver driver;
  final GoRouter router;
  final String recordId;
}

class _DetailObserver extends NavigatorObserver {
  int detailPops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route.settings.name == 'detail') {
      detailPops++;
    }
  }
}

Future<_Harness> _pumpDetail(
  WidgetTester tester, {
  ViewerDriver? driver,
  ViewerBuilder? viewerBuilder,
  bool validateStoredModels = false,
  Duration watchdog = const Duration(seconds: 8),
  String recordId = AvatarDetailScreen.sampleId,
  List<GenerationRecord> records = const <GenerationRecord>[],
}) async {
  final ViewerDriver viewer = driver ?? ViewerDriver();
  final _DetailObserver observer = _DetailObserver();
  final GoRouter router = GoRouter(
    observers: <NavigatorObserver>[observer],
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/avatars/$recordId'),
              child: const Text('open'),
            ),
          ),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'avatars/:id',
            name: 'detail',
            builder: (BuildContext context, GoRouterState state) =>
                AvatarDetailScreen(
                  recordId: state.pathParameters['id']!,
                  viewerBuilder: viewerBuilder ?? viewer.build,
                  watchdogDuration: watchdog,
                ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
      initialRecordsProvider.overrideWithValue(records),
      clockProvider.overrideWithValue(() => testNow),
    ],
  );
  addTearDown(container.dispose);
  if (validateStoredModels) {
    await tester.runAsync(
      () => container
          .read(libraryControllerProvider.notifier)
          .resumeInterrupted(),
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: AppTheme.dark),
    ),
  );
  final _Harness harness = _Harness(observer, viewer, router, recordId);
  await _open(tester, harness);
  return harness;
}

class _HostCallbacks {
  _HostCallbacks(this.registerReload, this.registerProbe, this.onLifecycle);

  final ValueChanged<Future<void> Function()> registerReload;
  final ValueChanged<Future<bool> Function()> registerProbe;
  final ValueChanged<ViewerLifecycleEvent> onLifecycle;
}

class _HostRecorder {
  final List<_HostCallbacks> calls = <_HostCallbacks>[];

  Widget build(
    ValueChanged<Future<void> Function()> registerReload,
    ValueChanged<Future<bool> Function()> registerProbe,
    ValueChanged<ViewerLifecycleEvent> onLifecycle,
  ) {
    calls.add(_HostCallbacks(registerReload, registerProbe, onLifecycle));
    return const ColoredBox(color: Colors.black);
  }
}

Future<void> _open(WidgetTester tester, _Harness harness) async {
  await tester.tap(find.text('open'));
  // The loading spinner never settles: advance the page transition by time.
  await settleFrames(tester);
  expect(find.byType(AvatarDetailScreen), findsOneWidget);
}
