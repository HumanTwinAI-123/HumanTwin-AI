import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/features/capture/photo_selection_screen.dart';
import 'package:human_twin_ai/features/capture/review_screen.dart';
import 'package:human_twin_ai/features/generation/task_screen.dart';
import 'package:human_twin_ai/features/library/avatar_detail_screen.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/settings/app_settings.dart';
import 'package:image_picker/image_picker.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'Creating a simulated avatar: guide, photos, review, progress, result',
    (WidgetTester tester) async {
      configureView(tester, const Size(390, 844));
      final TestApp app = await pumpApp(tester);

      await tester.tap(find.text('开始创建'));
      await settleFrames(tester);
      expect(find.text('拍摄说明'), findsOneWidget);
      expect(find.textContaining('未满 14 周岁'), findsOneWidget);
      await tester.tap(find.text('开始选择照片'));
      await settleFrames(tester);

      expect(find.byType(PhotoSelectionScreen), findsOneWidget);
      expect(find.text('已添加 0/3 · 还差：正面、侧面、背面'), findsOneWidget);
      await _addPhoto(tester, '正面');
      expect(find.text('已添加 1/3 · 还差：侧面、背面'), findsOneWidget);
      await _addPhoto(tester, '侧面');
      await _addPhoto(tester, '背面');
      expect(find.text('三张照片已就绪'), findsOneWidget);
      expect(app.picker.picks, 3);

      await tester.tap(find.text('下一步'));
      await settleFrames(tester);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('示例形象 9月30日'), findsOneWidget);
      expect(find.text('模拟生成约 5 秒，不会上传照片，也不消耗额度。'), findsOneWidget);

      await tester.tap(find.text('开始模拟生成'));
      await settleFrames(tester, frames: 3);
      expect(find.byType(TaskScreen), findsOneWidget);
      expect(app.photos.isEmpty, isTrue, reason: 'the draft was handed off');
      expect(app.library.records.single.status, isNot(RecordStatus.done));

      await tester.pump(const Duration(seconds: 3));
      await settleFrames(tester);
      final GenerationRecord done = app.library.records.single;
      expect(done.status, RecordStatus.done);
      expect(done.isSimulated, isTrue);
      expect(app.repository.createCount, 1);
      expect(app.store.savedRecords, hasLength(1));

      await tester.tap(find.text('查看形象'));
      await settleFrames(tester);
      expect(find.byType(AvatarDetailScreen), findsOneWidget);
      expect(find.text('这是示例模型'), findsOneWidget);
    },
  );

  testWidgets('Deleting a photo offers undo, and leaving keeps the draft', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(tester, showGuide: false);

    await tester.tap(find.text('开始创建'));
    await settleFrames(tester);
    expect(find.byType(PhotoSelectionScreen), findsOneWidget);
    await _addPhoto(tester, '正面');
    final XFile front = app.photos.front!;

    await tester.tap(find.text('正面'));
    await settleFrames(tester);
    expect(find.text('更换正面照片'), findsOneWidget);
    await tester.tap(find.text('删除这张照片'));
    await settleFrames(tester);
    expect(app.photos.front, isNull);
    expect(find.text('已删除正面照片'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await settleFrames(tester);
    expect(app.photos.front!.path, front.path);

    await tester.tap(find.byTooltip('返回'));
    await settleFrames(tester);
    expect(find.text('已保存为草稿，可在首页继续'), findsOneWidget);
    expect(find.text('继续创建形象'), findsOneWidget);

    // The draft goes straight back to photo selection.
    await tester.tap(find.text('继续'));
    await settleFrames(tester);
    expect(find.byType(PhotoSelectionScreen), findsOneWidget);
    expect(find.text('已添加 1/3 · 还差：侧面、背面'), findsOneWidget);
  });

  testWidgets('「下次不再显示拍摄说明」 skips the guide next time', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(tester);

    await tester.tap(find.text('开始创建'));
    await settleFrames(tester);
    await tester.tap(find.text('下次不再显示拍摄说明'));
    await tester.pump();
    await tester.tap(find.text('开始选择照片'));
    await settleFrames(tester);
    expect(app.container.read(appSettingsProvider).showGuide, isFalse);
    expect(find.byType(PhotoSelectionScreen), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await settleFrames(tester);
    await tester.tap(find.text('开始创建'));
    await settleFrames(tester);
    expect(find.byType(PhotoSelectionScreen), findsOneWidget);
    expect(find.text('拍摄说明'), findsNothing);
  });

  testWidgets('A busy generation keeps the review page from submitting', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(
      tester,
      showGuide: false,
      records: <GenerationRecord>[
        GenerationRecord(
          id: 'rrun',
          name: '进行中的形象',
          createdAt: testNow,
          mode: GenerationMode.mock,
          status: RecordStatus.processing,
          taskId: 'mock-1',
        ),
      ],
      draft: _completeDraft,
      mockDelay: const Duration(seconds: 30),
    );
    expect(app.library.blocking, hasLength(1));

    await tester.tap(find.text('继续'));
    await settleFrames(tester);
    await tester.tap(find.text('下一步'));
    await settleFrames(tester);
    expect(find.text('已有 1 个生成任务未结束'), findsOneWidget);
    final FilledButton submit = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('开始模拟生成'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(submit.onPressed, isNull);

    // Let the resumed simulation finish so no timers outlive the test.
    await tester.pump(const Duration(seconds: 31));
    await settleFrames(tester);
  });

  for (final (Size size, double scale, String label)
      in <(Size, double, String)>[
        (const Size(360, 640), 2, '360 dp at 200% text'),
        (const Size(360, 560), 1, 'a short 360×560 screen'),
      ]) {
    testWidgets('Creation pages fit $label', (WidgetTester tester) async {
      configureView(tester, size, textScale: scale);
      final TestApp app = await pumpApp(tester, draft: _completeDraft);
      expectNoLayoutErrors(tester, 'home');

      await tester.tap(find.text('继续'));
      await settleFrames(tester);
      expectNoLayoutErrors(tester, 'photos');
      expect(find.text('下一步'), findsOneWidget);
      if (scale > 1.5) {
        // Large text switches the three slots to a single-column list.
        expect(find.text('点按更换'), findsNWidgets(3));
      }

      await tester.tap(find.text('下一步'));
      await settleFrames(tester);
      expectNoLayoutErrors(tester, 'review');
      expect(find.text('开始模拟生成'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('接下来会发生什么'),
        200,
        scrollable: scrollableIn(ReviewScreen),
      );
      await tester.pump();
      expectNoLayoutErrors(tester, 'review scrolled');

      await tester.tap(find.text('开始模拟生成'));
      await settleFrames(tester, frames: 3);
      expectNoLayoutErrors(tester, 'progress');
      await tester.pump(const Duration(seconds: 3));
      await settleFrames(tester);
      expectNoLayoutErrors(tester, 'result');
      expect(app.library.records.single.isDone, isTrue);
    });
  }
}

final Map<PhotoAngle, XFile> _completeDraft = <PhotoAngle, XFile>{
  PhotoAngle.front: XFile('/draft/front.jpg'),
  PhotoAngle.side: XFile('/draft/side.jpg'),
  PhotoAngle.back: XFile('/draft/back.jpg'),
};

Future<void> _addPhoto(WidgetTester tester, String angle) async {
  await tester.tap(find.text(angle));
  await settleFrames(tester);
  await tester.tap(find.text('从相册选择'));
  await settleFrames(tester);
}
