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

  testWidgets('opens the completed Photo Guide and returns to Home', (
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
    expect(find.text('按标准完成三视图拍摄'), findsOneWidget);
    expect(find.text('正面\nFRONT'), findsOneWidget);
    expect(find.text('侧面\nSIDE'), findsOneWidget);
    expect(find.text('背面\nBACK'), findsOneWidget);
    expect(find.text('拍摄要求'), findsOneWidget);
    expect(find.text('• 光线均匀，避免强逆光和明显阴影'), findsOneWidget);
    expect(find.text('• 全身完整入镜，头部与双脚不要裁切'), findsOneWidget);
    expect(find.text('• 身体自然站立，手臂与躯干轻微分开'), findsOneWidget);
    expect(find.text('• 背景保持整洁，避免宽松或反光服装'), findsOneWidget);
    expect(find.text('我已了解'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('创建你的\n数字人体'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('digital-human-static-hero')),
      findsOneWidget,
    );
  });

  testWidgets('Photo Guide primary action opens the Day 4 placeholder', (
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
    await tester.tap(find.text('我已了解'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('photo-selection-placeholder')),
      findsOneWidget,
    );
    expect(find.text('DAY 4 · PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('Photo Guide stays usable at 360dp and 200% text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 650);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    app.main();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Home overflowed');

    await tester.ensureVisible(find.text('开始创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始创建'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('photo-guide-scroll')),
      findsOneWidget,
    );
    expect(find.text('拍摄说明'), findsOneWidget);
    expect(find.text('我已了解'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('稍后'),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('photo-guide-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('• 背景保持整洁，避免宽松或反光服装'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('我已了解'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('photo-selection-placeholder')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
