import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/capture/photo_guide_screen.dart';
import 'package:human_twin_ai/features/capture/photo_selection_screen.dart';
import 'package:human_twin_ai/features/home/home_screen.dart';
import 'package:human_twin_ai/main.dart' as app;
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'support/harness.dart';

void main() {
  /// Runs the real entry point. Without the platform channel it falls back to a throwaway
  /// temporary store, which is removed after the test.
  Future<void> launch(WidgetTester tester) async {
    final Set<String> before = _humanTwinTempDirs();
    addTearDown(() {
      for (final String path in _humanTwinTempDirs().difference(before)) {
        Directory(path).deleteSync(recursive: true);
      }
    });
    await tester.runAsync(app.main);
    await settleFrames(tester);
  }

  testWidgets(
    'A fresh install opens the welcome page, then the first-run Home',
    (WidgetTester tester) async {
      configureView(tester, const Size(390, 844));
      await launch(tester);

      expect(find.text('开始使用'), findsOneWidget);
      expect(find.byType(ModelViewer), findsNothing);
      await tester.tap(find.text('开始使用'));
      // Onboarding is saved to real storage before Home opens.
      await waitFor(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
      );

      expect(find.text('开始创建'), findsOneWidget);
      expect(find.text('先看看示例形象'), findsOneWidget);
      expect(find.text('首页'), findsOneWidget);
    },
  );

  testWidgets(
    'The guide leads to photo selection and fits 360 dp at 200% text',
    (WidgetTester tester) async {
      configureView(tester, const Size(360, 650), textScale: 2);
      await launch(tester);
      await tester.tap(find.text('开始使用'));
      // Onboarding is saved to real storage before Home opens.
      await waitFor(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
      );
      expectNoLayoutErrors(tester, 'home');

      await tester.scrollUntilVisible(
        find.text('开始创建'),
        160,
        scrollable: scrollableIn(HomeScreen),
      );
      await tester.tap(find.text('开始创建'));
      await settleFrames(tester);
      expect(find.byType(PhotoGuideScreen), findsOneWidget);
      expectNoLayoutErrors(tester, 'guide');
      await tester.scrollUntilVisible(
        find.textContaining('未满 14 周岁'),
        160,
        scrollable: scrollableIn(PhotoGuideScreen),
      );
      await tester.pump();
      expect(find.text('背景整洁，避免宽松或反光的衣服'), findsOneWidget);
      expectNoLayoutErrors(tester, 'guide scrolled');

      await tester.tap(find.text('开始选择照片'));
      await settleFrames(tester);
      expect(find.byType(PhotoSelectionScreen), findsOneWidget);
      expectNoLayoutErrors(tester, 'photos');
    },
  );

  testWidgets('The 3D proof-of-concept page opens, exits and reopens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      app.HumanTwinPocApp(
        modelViewerBuilder: () => const ColoredBox(
          key: ValueKey<String>('test-model-viewer'),
          color: Colors.black,
        ),
      ),
    );

    expect(find.text('HumanTwin AI 3D POC'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('open-viewer-button')));
    await tester.pumpAndSettle();
    expect(find.byType(app.DigitalTwinViewerPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('test-model-viewer')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('HumanTwin AI 3D POC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('open-viewer-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('test-model-viewer')),
      findsOneWidget,
    );
  });

  test(
    'The bundled model viewer enables every required camera interaction',
    () {
      final ModelViewer viewer = app.buildHumanModelViewer();

      expect(viewer.src, 'assets/models/human_demo.glb');
      expect(viewer.cameraControls, isTrue);
      expect(viewer.autoRotate, isTrue);
      expect(viewer.disableZoom, isFalse);
      expect(viewer.loading, Loading.eager);
      expect(viewer.debugLogging, isFalse);
    },
  );
}

Set<String> _humanTwinTempDirs() => Directory.systemTemp
    .listSync()
    .whereType<Directory>()
    .where(
      (Directory d) =>
          d.path.split(Platform.pathSeparator).last.startsWith('humantwin-'),
    )
    .map((Directory d) => d.path)
    .toSet();
