import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/app/theme/app_theme.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/library/library_controller.dart';
import 'package:human_twin_ai/features/library/record_widgets.dart';
import 'package:human_twin_ai/features/share/share_controller.dart';
import 'package:human_twin_ai/shared/storage/local_store.dart';
import 'package:human_twin_ai/shared/ui/ht_ui.dart';

import 'support/harness.dart';

/// Regressions found by the v1 implementation review.
void main() {
  group('storage', () {
    late Directory temp;
    late LocalStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ht-review-');
      store = await LocalStore.open(
        documentsPath: '${temp.path}/docs',
        cachePath: '${temp.path}/cache',
      );
    });

    tearDown(() => temp.delete(recursive: true));

    test(
      'clearing all data empties the folder but keeps the folder itself',
      () async {
        // iOS marks this folder "excluded from backup"; a recreated folder would lose that.
        final File marker = File('${store.root.path}/.created')
          ..writeAsStringSync('x');
        final DateTime created = store.root.statSync().changed;
        store.recordDir('r1').createSync(recursive: true);
        File('${store.recordDir('r1').path}/model.glb').writeAsStringSync('m');
        final File export = await store.exportFile('a.png')
          ..writeAsStringSync('p');

        await store.clearAll();

        expect(store.root.existsSync(), isTrue);
        expect(marker.existsSync(), isFalse);
        expect(store.recordDir('r1').existsSync(), isFalse);
        expect(export.existsSync(), isFalse);
        expect(store.recordsDir.existsSync(), isTrue);
        expect(store.draftDir.existsSync(), isTrue);
        expect(store.root.statSync().changed.isBefore(created), isFalse);
      },
    );

    test('a damaged index is kept aside before a new one is written', () async {
      store.file(LibraryController.fileName).writeAsStringSync('{broken');
      expect(await LibraryController.indexIntact(store), isFalse);

      await LibraryController.preserveDamagedIndex(store);

      expect(store.file(LibraryController.fileName).existsSync(), isFalse);
      expect(
        store.root.listSync().map((FileSystemEntity e) => e.path),
        contains(contains('library.json.damaged-')),
      );
    });

    test(
      'deleting an avatar also deletes the copies exported from it',
      () async {
        final ProviderContainer container = ProviderContainer(
          overrides: [localStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        final ShareController share = container.read(
          shareControllerProvider.notifier,
        );
        final GenerationRecord record = doneRecord('rexp');
        final PreparedExport png = await share.writeImage(
          record,
          File('assets/images/thumb_sample.png').readAsBytesSync(),
        );
        expect(png.file.existsSync(), isTrue);

        share.forget('rexp');
        for (int i = 0; i < 20 && png.file.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(png.file.existsSync(), isFalse);
      },
    );
  });

  test('storage totals count only model files the avatars themselves keep', () {
    final List<GenerationRecord> demo = <GenerationRecord>[
      doneRecord('a'),
      doneRecord('b'),
    ];
    expect(storedModelBytes(demo), 0, reason: 'they share the bundled sample');
    expect(avatarStorageSummary(demo), '2 个形象');

    final GenerationRecord own = doneRecord('c', mode: GenerationMode.service)
        .copyWith(
          model: const ModelRef.file('records/c/model.glb'),
          modelBytes: 3 * 1024 * 1024,
        );
    expect(
      avatarStorageSummary(<GenerationRecord>[...demo, own]),
      '3 个形象 · 3.0 MB',
    );
  });

  testWidgets('Fact labels of up to four characters stay on one line', (
    WidgetTester tester,
  ) async {
    for (final double scale in <double>[1, 1.3]) {
      configureView(tester, const Size(360, 640), textScale: scale);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: FactTable(
              rows: <FactRow>[
                FactRow(icon: Icons.pause_rounded, label: '停止查询', value: '值'),
                FactRow(icon: Icons.share_outlined, label: '分享后', value: '值'),
              ],
            ),
          ),
        ),
      );
      final double lineHeight = tester.getSize(find.text('值').first).height;
      expect(tester.getSize(find.text('停止查询')).height, lineHeight);
      expect(tester.getSize(find.text('分享后')).height, lineHeight);
    }
  });

  testWidgets('Page content ends above the edge-to-edge navigation bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
          child: PageBody(children: <Widget>[Text('最后一行')]),
        ),
      ),
    );
    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect((list.padding! as EdgeInsets).bottom, AppSpacing.xl + 48);
  });

  testWidgets('Home names that wrap at 130% and 200% text do not overflow', (
    WidgetTester tester,
  ) async {
    for (final (Size size, double scale) in <(Size, double)>[
      (const Size(320, 640), 1.3),
      (const Size(360, 640), 2),
    ]) {
      configureView(tester, size, textScale: scale);
      await pumpApp(
        tester,
        records: <GenerationRecord>[
          doneRecord('r1', name: '示例形象 10月12日 (2)', seen: false),
          doneRecord('r2', name: '示例形象 9月30日'),
        ],
      );
      await tester.scrollUntilVisible(
        find.text('示例形象 9月30日'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expectNoLayoutErrors(tester, 'home at $scale');
    }
  });

  testWidgets(
    'A record from the other build mode explains itself instead of failing silently',
    (WidgetTester tester) async {
      configureView(tester, const Size(390, 844));
      final TestApp app = await pumpApp(
        tester,
        records: <GenerationRecord>[
          GenerationRecord(
            id: 'rsvc',
            name: '服务端任务',
            createdAt: testNow,
            mode: GenerationMode.service,
            status: RecordStatus.paused,
            taskId: 'task-1',
            origin: ModelOrigin.serviceGenerated,
          ),
        ],
        initialLocation: '/tasks/rsvc',
      );

      expect(find.textContaining('当前版本无法继续处理'), findsOneWidget);
      expect(find.text('继续查询'), findsNothing);
      await tester.tap(find.text('从本机移除'));
      await settleFrames(tester);
      await tester.tap(find.widgetWithText(TextButton, '移除'));
      await settleFrames(tester);
      expect(app.library.byId('rsvc'), isNull);
    },
  );
}
