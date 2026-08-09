import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/main.dart' as app;
import 'package:model_viewer_plus/model_viewer_plus.dart';

void main() {
  testWidgets('app entrypoint shows the static Day 2 home screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    app.main();
    await tester.pumpAndSettle();

    expect(find.text('创建你的\n数字人体'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('digital-human-static-hero')),
      findsOneWidget,
    );
    expect(find.byType(ModelViewer), findsNothing);
  });

  testWidgets('primary action opens the Photo Guide placeholder', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始创建'));
    await tester.pumpAndSettle();

    expect(find.text('拍摄说明'), findsOneWidget);
    expect(find.text('Photo Guide 将在 Day 3 完成'), findsOneWidget);
  });

  testWidgets('opens, exits, and reopens the 3D viewer', (
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

    expect(find.byType(app.DigitalTwinViewerPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('test-model-viewer')),
      findsOneWidget,
    );
  });

  test('bundled model viewer enables every required camera interaction', () {
    final ModelViewer viewer = app.buildHumanModelViewer();

    expect(viewer.src, 'assets/models/human_demo.glb');
    expect(viewer.cameraControls, isTrue);
    expect(viewer.autoRotate, isTrue);
    expect(viewer.disableZoom, isFalse);
    expect(viewer.loading, Loading.eager);
    expect(viewer.backgroundColor, const Color(0xFFDDE6F2));
  });
}
