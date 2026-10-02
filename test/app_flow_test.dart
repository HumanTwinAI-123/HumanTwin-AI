import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/capture/review_screen.dart';
import 'package:human_twin_ai/features/home/home_screen.dart';
import 'package:human_twin_ai/features/library/avatar_detail_screen.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/library/library_screen.dart';
import 'package:human_twin_ai/features/settings/app_settings.dart';
import 'package:human_twin_ai/features/settings/settings_screens.dart';
import 'package:human_twin_ai/features/viewer/digital_twin_viewer.dart';

import 'support/harness.dart';

void main() {
  testWidgets('First launch: welcome once, then the first-run Home', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(tester, onboarded: false);

    expect(find.text('开始使用'), findsOneWidget);
    expect(find.text('默认私密'), findsOneWidget);
    await tester.tap(find.text('开始使用'));
    await settleFrames(tester);

    expect(app.container.read(appSettingsProvider).onboardingDone, isTrue);
    expect(app.store.files[AppSettings.fileName]?['onboardingDone'], isTrue);
    expect(find.text('开始创建'), findsOneWidget);
    expect(find.text('先看看示例形象'), findsOneWidget);

    await tester.tap(find.text('先看看示例形象'));
    await settleFrames(tester);
    expect(find.byType(AvatarDetailScreen), findsOneWidget);
    expect(find.text('内置示例模型'), findsOneWidget);
  });

  testWidgets(
    'Returning Home announces results and items that need attention',
    (WidgetTester tester) async {
      configureView(tester, const Size(390, 844));
      final TestApp app = await pumpApp(tester, records: _records);

      expect(find.text('形象已保存'), findsOneWidget);
      expect(find.text('需要你处理'), findsOneWidget);
      expect(find.text('模拟失败的形象'), findsWidgets);

      // Opening the new result clears the announcement.
      await tester.tap(find.text('查看'));
      await settleFrames(tester);
      expect(find.byType(AvatarDetailScreen), findsOneWidget);
      expect(app.library.byId('rnew')!.resultSeen, isTrue);
    },
  );

  testWidgets('My avatars: filters, rename and delete stay on this phone', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(tester, records: _records);

    await tester.tap(find.text('我的形象').last);
    await settleFrames(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('全部 3'), findsOneWidget);
    expect(find.text('需处理 1'), findsOneWidget);
    expect(find.text('已完成 2'), findsOneWidget);

    await tester.tap(find.text('需处理 1'));
    await tester.pump();
    expect(find.text('模拟失败的形象'), findsOneWidget);
    expect(find.text('跑步前的形象'), findsNothing);
    await tester.tap(find.text('全部 3'));
    await tester.pump();

    await tester.tap(find.text('跑步前的形象'));
    await settleFrames(tester);
    expect(find.byType(AvatarDetailScreen), findsOneWidget);
    app.viewer.send(ViewerLifecycleEvent.modelLoaded);
    await tester.pump();

    await tester.tap(find.byTooltip('重命名'));
    await settleFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-field')),
      '晨跑形象',
    );
    await tester.tap(find.text('保存'));
    await settleFrames(tester);
    expect(app.library.byId('rold')!.name, '晨跑形象');
    expect(
      (app.store.savedRecords.firstWhere(
            (Object? r) => (r! as Map<String, Object?>)['id'] == 'rold',
          )!
          as Map<String, Object?>)['name'],
      '晨跑形象',
    );

    await tester.tap(find.byTooltip('更多操作'));
    await settleFrames(tester);
    await tester.tap(find.text('删除').last);
    await settleFrames(tester);
    expect(find.text('删除「晨跑形象」？'), findsOneWidget);
    expect(find.textContaining('已经分享或导出的文件不会被撤回'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await settleFrames(tester);

    expect(app.library.byId('rold'), isNull);
    expect(app.store.deletedRecords, contains('rold'));
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('全部 2'), findsOneWidget);
  });

  testWidgets('A failed simulation can be retried with the same photos', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(
      tester,
      records: _records,
      initialLocation: '/tasks/rfail',
    );

    expect(find.text('重新模拟生成'), findsOneWidget);
    await tester.tap(find.text('重新模拟生成'));
    await settleFrames(tester);
    expect(find.text('重新模拟生成？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '重新模拟'));
    await settleFrames(tester);

    expect(app.library.byId('rfail'), isNull);
    expect(app.photos.isComplete, isTrue);
    expect(find.byType(ReviewScreen), findsOneWidget);
  });

  testWidgets('Settings: guide switch, privacy page and clearing all data', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final TestApp app = await pumpApp(tester, records: _records);

    await tester.tap(find.text('设置').last);
    await settleFrames(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('版本 0.1.0'), findsOneWidget);

    await tester.tap(find.text('创建前显示拍摄说明'));
    await tester.pump();
    expect(app.container.read(appSettingsProvider).showGuide, isFalse);

    await tester.tap(find.text('隐私与数据').last);
    await settleFrames(tester);
    expect(find.byType(PrivacyScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('清除全部本机数据'),
      200,
      scrollable: scrollableIn(PrivacyScreen),
    );
    await tester.tap(find.text('清除全部本机数据'));
    await settleFrames(tester);
    expect(find.text('清除全部本机数据？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '全部清除'));
    await settleFrames(tester);

    expect(app.library.records, isEmpty);
    expect(app.store.clears, 1);
    expect(app.container.read(appSettingsProvider).onboardingDone, isTrue);
    expect(find.text('已清除全部本机数据'), findsOneWidget);
  });

  for (final (Size size, double scale, String label)
      in <(Size, double, String)>[
        (const Size(360, 640), 2, '360 dp at 200% text'),
        (const Size(360, 560), 1, 'a short 360×560 screen'),
        (const Size(320, 568), 1.3, '320 dp at 130% text'),
      ]) {
    testWidgets('Main screens fit $label', (WidgetTester tester) async {
      configureView(tester, size, textScale: scale);
      await pumpApp(tester, onboarded: false);
      expectNoLayoutErrors(tester, 'welcome');
      await tester.tap(find.text('开始使用'));
      await settleFrames(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expectNoLayoutErrors(tester, 'first home');

      await pumpApp(tester, records: _records);
      expectNoLayoutErrors(tester, 'home');

      await tester.tap(find.text('我的形象').last);
      await settleFrames(tester);
      expectNoLayoutErrors(tester, 'library');
      if (scale >= 1.5) {
        // Large text lists the items in one column with a visible status chip.
        expect(find.text('未成功'), findsWidgets);
      }

      await tester.tap(find.text('设置').last);
      await settleFrames(tester);
      expectNoLayoutErrors(tester, 'settings');
      for (final (String page, String scrollTo) in <(String, String)>[
        // The heading 隐私与数据 precedes the item of the same name: scroll past it.
        ('隐私与数据', '存储空间'),
        ('常见问题', '常见问题'),
        ('关于 HumanTwin AI', '关于 HumanTwin AI'),
      ]) {
        await tester.scrollUntilVisible(
          find.text(scrollTo),
          150,
          scrollable: scrollableIn(SettingsScreen),
        );
        await tester.tap(find.text(page).last);
        await settleFrames(tester);
        expectNoLayoutErrors(tester, page);
        await tester.tap(find.byTooltip('返回'));
        await settleFrames(tester);
      }

      await tester.tap(find.text('首页').last);
      await settleFrames(tester);
      await tester.tap(find.text('模拟失败的形象').first);
      await settleFrames(tester);
      expectNoLayoutErrors(tester, 'task recovery');
    });
  }
}

final List<GenerationRecord> _records = <GenerationRecord>[
  doneRecord(
    'rnew',
    name: '刚完成的形象',
    seen: false,
    createdAt: DateTime(2026, 9, 30, 14),
  ),
  doneRecord('rold', name: '跑步前的形象', createdAt: DateTime(2026, 9, 28, 9)),
  GenerationRecord(
    id: 'rfail',
    name: '模拟失败的形象',
    createdAt: DateTime(2026, 9, 30, 12),
    mode: GenerationMode.mock,
    status: RecordStatus.failed,
    taskId: 'mock-9',
    inputs: const <String>['/r/front.jpg', '/r/side.jpg', '/r/back.jpg'],
  ),
];
