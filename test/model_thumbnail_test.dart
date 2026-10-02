import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/library/record_widgets.dart';
import 'package:human_twin_ai/shared/storage/local_store.dart';

import 'support/harness.dart';

void main() {
  GenerationRecord record(ModelRef model) => GenerationRecord(
    id: 'model-provenance',
    name: '示例形象',
    createdAt: DateTime(2026, 10, 1),
    mode: GenerationMode.mock,
    status: RecordStatus.done,
    origin: ModelOrigin.simulatedSample,
    model: model,
  );

  Future<void> show(WidgetTester tester, ModelRef model) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(MemoryLocalStore())],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 225,
              child: AvatarThumbnail(record: record(model)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  int currentSampleImages(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .where(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName == sampleThumbnailAsset,
      )
      .length;

  testWidgets('bundled sample shows its current Blender thumbnail', (
    tester,
  ) async {
    await show(tester, const ModelRef.asset(sampleModelAsset));
    expect(currentSampleImages(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'older downloaded sample never borrows the new avatar thumbnail',
    (tester) async {
      await show(tester, const ModelRef.file('records/legacy/model.glb'));
      expect(currentSampleImages(tester), 0);
      expect(find.text('示例模型'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
