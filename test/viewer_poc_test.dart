import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/main.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

void main() {
  testWidgets('opens, exits, and reopens the 3D viewer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      HumanTwinPocApp(
        modelViewerBuilder: () => const ColoredBox(
          key: ValueKey<String>('test-model-viewer'),
          color: Colors.black,
        ),
      ),
    );

    expect(find.text('HumanTwin AI 3D POC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('open-viewer-button')));
    await tester.pumpAndSettle();

    expect(find.byType(DigitalTwinViewerPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('test-model-viewer')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('HumanTwin AI 3D POC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('open-viewer-button')));
    await tester.pumpAndSettle();

    expect(find.byType(DigitalTwinViewerPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('test-model-viewer')),
      findsOneWidget,
    );
  });

  test('bundled model viewer enables every required camera interaction', () {
    final ModelViewer viewer = buildHumanModelViewer();

    expect(viewer.src, 'assets/models/human_demo.glb');
    expect(viewer.cameraControls, isTrue);
    expect(viewer.autoRotate, isTrue);
    expect(viewer.disableZoom, isFalse);
    expect(viewer.loading, Loading.eager);
    expect(viewer.backgroundColor, const Color(0xFFDDE6F2));
  });
}
