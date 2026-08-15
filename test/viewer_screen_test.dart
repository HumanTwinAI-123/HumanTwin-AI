import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:human_twin_ai/app/app.dart';
import 'package:human_twin_ai/app/theme/app_theme.dart';
import 'package:human_twin_ai/features/viewer/digital_twin_viewer.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

void main() {
  test(
    'Production Viewer registers one lifecycle channel and its DOM bridge',
    () {
      final ModelViewer viewer = buildHumanModelViewer(
        poster: 'data:image/png;base64,approved-poster',
      );

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

  testWidgets('Production router exposes the injected Viewer route', (
    WidgetTester tester,
  ) async {
    final GoRouter router = createAppRouter(
      viewerBuilder: (BuildContext context) => const ColoredBox(
        key: ValueKey<String>('injected-viewer-route'),
        color: Colors.black,
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.dark),
    );
    router.go('/viewer');
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/viewer');
    expect(
      find.byKey(const ValueKey<String>('injected-viewer-route')),
      findsOneWidget,
    );
    expect(find.byType(ModelViewer), findsNothing);
  });

  testWidgets('Viewer renders the approved content with a fake model host', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ViewerScreen(
          viewerBuilder:
              (registerReload, registerReadinessProbe, onLifecycleEvent) =>
                  _RegisteringFakeViewer(
                    registerReload: registerReload,
                    registerReadinessProbe: registerReadinessProbe,
                    onReload: () async {},
                    onProbe: () async => false,
                  ),
        ),
      ),
    );

    expect(find.text('数字人体'), findsOneWidget);
    expect(find.text('06 / 06'), findsOneWidget);
    expect(find.text('DIGITAL HUMAN · LOCAL MODEL'), findsOneWidget);
    expect(find.text('拖动旋转 · 双指缩放 · 自动旋转'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('viewer-host')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fake-viewer-content')),
      findsOneWidget,
    );
    expect(find.byType(ModelViewer), findsNothing);
  });

  testWidgets('Reload stays disabled until registered and invokes once', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(390, 844));
    int reloadCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ViewerScreen(
          viewerBuilder:
              (registerReload, registerReadinessProbe, onLifecycleEvent) =>
                  _RegisteringFakeViewer(
                    registerReload: registerReload,
                    registerReadinessProbe: registerReadinessProbe,
                    onReload: () async => reloadCalls++,
                    onProbe: () async => false,
                  ),
        ),
      ),
    );

    final Finder reload = find.byKey(const ValueKey<String>('viewer-reload'));
    expect(reload, findsOneWidget);

    await tester.tap(reload);
    await tester.pump();
    expect(reloadCalls, 0);

    await tester.tap(reload);
    await tester.pump();
    expect(reloadCalls, 1);
  });

  testWidgets('System back stays on Viewer while initialization is unsafe', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver();
    final _ViewerRouteHarness harness = await _pumpViewerRoute(tester, driver);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('数字人体'), findsOneWidget);
    expect(harness.observer.viewerPops, 0);
  });

  testWidgets('Pending UI back returns once when page-ready arrives', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver();
    final _ViewerRouteHarness harness = await _pumpViewerRoute(tester, driver);

    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.pump();
    expect(find.text('数字人体'), findsOneWidget);
    expect(harness.observer.viewerPops, 0);

    driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('open-test-viewer')),
      findsOneWidget,
    );
    expect(harness.observer.viewerPops, 1);
  });

  for (final ViewerLifecycleEvent event in <ViewerLifecycleEvent>[
    ViewerLifecycleEvent.modelLoaded,
    ViewerLifecycleEvent.modelError,
  ]) {
    testWidgets('Pending exit returns once when ${event.name} arrives', (
      WidgetTester tester,
    ) async {
      final _ViewerDriver driver = _ViewerDriver();
      final _ViewerRouteHarness harness = await _pumpViewerRoute(
        tester,
        driver,
      );

      await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
      await tester.pump();
      driver.send(event);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('open-test-viewer')),
        findsOneWidget,
      );
      expect(find.text('加载完成'), findsNothing);
      expect(harness.observer.viewerPops, 1);
    });
  }

  testWidgets('Repeated and mixed early back requests produce one pop', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver();
    final _ViewerRouteHarness harness = await _pumpViewerRoute(tester, driver);

    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(harness.observer.viewerPops, 0);

    driver.send(ViewerLifecycleEvent.pageReady);
    driver.send(ViewerLifecycleEvent.modelLoaded);
    driver.send(ViewerLifecycleEvent.modelError);
    await tester.pumpAndSettle();

    expect(harness.observer.viewerPops, 1);
    expect(
      find.byKey(const ValueKey<String>('open-test-viewer')),
      findsOneWidget,
    );
  });

  testWidgets('Ready before back allows immediate UI and system returns', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver();
    final _ViewerRouteHarness harness = await _pumpViewerRoute(tester, driver);

    driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.pumpAndSettle();
    expect(harness.observer.viewerPops, 1);

    await tester.tap(find.byKey(const ValueKey<String>('open-test-viewer')));
    await tester.pumpAndSettle();
    driver.send(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(harness.observer.viewerPops, 2);
    expect(
      find.byKey(const ValueKey<String>('open-test-viewer')),
      findsOneWidget,
    );
  });

  testWidgets('Watchdog timeout alone does not unlock exit', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver(probeResult: false);
    final _ViewerRouteHarness harness = await _pumpViewerRoute(
      tester,
      driver,
      watchdogDuration: const Duration(milliseconds: 100),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(driver.probeCalls, 1);

    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.pump();
    expect(find.text('数字人体'), findsOneWidget);
    expect(harness.observer.viewerPops, 0);
  });

  testWidgets('Watchdog positive probe releases one pending exit', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver(probeResult: true);
    final _ViewerRouteHarness harness = await _pumpViewerRoute(
      tester,
      driver,
      watchdogDuration: const Duration(milliseconds: 100),
    );

    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(driver.probeCalls, 1);
    expect(harness.observer.viewerPops, 1);
    expect(
      find.byKey(const ValueKey<String>('open-test-viewer')),
      findsOneWidget,
    );
  });

  testWidgets('Reload ignores an in-flight double tap and keeps exit safe', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(390, 844));
    final Completer<void> reloadCompletion = Completer<void>();
    final _ViewerDriver driver = _ViewerDriver(
      reloadAction: () => reloadCompletion.future,
    );
    final _ViewerRouteHarness harness = await _pumpViewerRoute(tester, driver);
    driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pump();

    final Finder reload = find.byKey(const ValueKey<String>('viewer-reload'));
    await tester.scrollUntilVisible(
      reload,
      220,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('viewer-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(reload);
    await tester.pump();
    await tester.tap(reload);
    await tester.pump();
    expect(driver.reloadCalls, 1);

    reloadCompletion.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.pumpAndSettle();

    expect(harness.observer.viewerPops, 1);
  });

  testWidgets('Stale lifecycle callback is ignored after guarded reopen', (
    WidgetTester tester,
  ) async {
    final _ViewerDriver driver = _ViewerDriver();
    final _ViewerRouteHarness harness = await _pumpViewerRoute(tester, driver);
    final ValueChanged<ViewerLifecycleEvent> staleCallback =
        driver.lifecycleCallback;
    driver.send(ViewerLifecycleEvent.pageReady);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('viewer-back')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('open-test-viewer')));
    await tester.pumpAndSettle();
    staleCallback(ViewerLifecycleEvent.modelError);
    await tester.pump();

    expect(find.text('数字人体'), findsOneWidget);
    expect(harness.observer.viewerPops, 1);

    driver.send(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(harness.observer.viewerPops, 2);
  });

  testWidgets('Ordinary rebuild keeps one Viewer host and its local state', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(390, 844));
    int viewerInitializations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ViewerScreen(
          viewerBuilder:
              (registerReload, registerReadinessProbe, onLifecycleEvent) =>
                  _StateTrackingFakeViewer(
                    onInitialize: () => viewerInitializations++,
                  ),
        ),
      ),
    );

    expect(viewerInitializations, 1);
    tester.view.physicalSize = const Size(389, 844);
    await tester.pump();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();

    expect(viewerInitializations, 1);
    expect(find.byKey(const ValueKey<String>('viewer-host')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('stateful-fake-viewer')),
      findsOneWidget,
    );
  });

  testWidgets('Viewer stays usable at 360dp and 200 percent text', (
    WidgetTester tester,
  ) async {
    _configureView(tester, const Size(360, 650), textScaleFactor: 2);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ViewerScreen(
          viewerBuilder:
              (registerReload, registerReadinessProbe, onLifecycleEvent) =>
                  const ColoredBox(
                    key: ValueKey<String>('responsive-fake-viewer'),
                    color: Colors.black,
                  ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('viewer-scroll')), findsOneWidget);
    expect(find.text('06 / 06'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('viewer-host'))).height,
      greaterThan(400),
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('viewer-reload')),
      220,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('viewer-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('拖动旋转 · 双指缩放 · 自动旋转'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<_ViewerRouteHarness> _pumpViewerRoute(
  WidgetTester tester,
  _ViewerDriver driver, {
  Duration watchdogDuration = const Duration(seconds: 8),
}) async {
  final _ViewerNavigatorObserver observer = _ViewerNavigatorObserver();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      navigatorObservers: <NavigatorObserver>[observer],
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const ValueKey<String>('open-test-viewer'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'viewer-test'),
                    builder: (BuildContext context) => ViewerScreen(
                      viewerBuilder: driver.build,
                      watchdogDuration: watchdogDuration,
                    ),
                  ),
                );
              },
              child: const Text('Open Viewer'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open-test-viewer')));
  await tester.pumpAndSettle();
  expect(find.text('数字人体'), findsOneWidget);
  return _ViewerRouteHarness(observer);
}

class _ViewerRouteHarness {
  const _ViewerRouteHarness(this.observer);

  final _ViewerNavigatorObserver observer;
}

class _ViewerNavigatorObserver extends NavigatorObserver {
  int viewerPops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route.settings.name == 'viewer-test') {
      viewerPops++;
    }
  }
}

class _ViewerDriver {
  _ViewerDriver({this.probeResult = false, this.reloadAction});

  final bool probeResult;
  final Future<void> Function()? reloadAction;
  late ValueChanged<ViewerLifecycleEvent> lifecycleCallback;
  int probeCalls = 0;
  int reloadCalls = 0;

  Widget build(
    ValueChanged<Future<void> Function()> registerReload,
    ValueChanged<Future<bool> Function()> registerReadinessProbe,
    ValueChanged<ViewerLifecycleEvent> onLifecycleEvent,
  ) {
    lifecycleCallback = onLifecycleEvent;
    return _RegisteringFakeViewer(
      registerReload: registerReload,
      registerReadinessProbe: registerReadinessProbe,
      onReload: () async {
        reloadCalls++;
        await reloadAction?.call();
      },
      onProbe: () async {
        probeCalls++;
        return probeResult;
      },
    );
  }

  void send(ViewerLifecycleEvent event) => lifecycleCallback(event);
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

class _RegisteringFakeViewer extends StatefulWidget {
  const _RegisteringFakeViewer({
    required this.registerReload,
    required this.registerReadinessProbe,
    required this.onReload,
    required this.onProbe,
  });

  final ValueChanged<Future<void> Function()> registerReload;
  final ValueChanged<Future<bool> Function()> registerReadinessProbe;
  final Future<void> Function() onReload;
  final Future<bool> Function() onProbe;

  @override
  State<_RegisteringFakeViewer> createState() => _RegisteringFakeViewerState();
}

class _RegisteringFakeViewerState extends State<_RegisteringFakeViewer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.registerReload(widget.onReload);
        widget.registerReadinessProbe(widget.onProbe);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey<String>('fake-viewer-content'),
      color: Colors.black,
    );
  }
}

class _StateTrackingFakeViewer extends StatefulWidget {
  const _StateTrackingFakeViewer({required this.onInitialize});

  final VoidCallback onInitialize;

  @override
  State<_StateTrackingFakeViewer> createState() =>
      _StateTrackingFakeViewerState();
}

class _StateTrackingFakeViewerState extends State<_StateTrackingFakeViewer> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey<String>('stateful-fake-viewer'),
      color: Colors.black,
    );
  }
}
