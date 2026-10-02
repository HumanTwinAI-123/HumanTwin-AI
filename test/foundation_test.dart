import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/settings/app_settings.dart';
import 'package:human_twin_ai/shared/platform/device_services.dart';
import 'package:human_twin_ai/shared/storage/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LocalStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ht-foundation-');
    store = await LocalStore.open(
      documentsPath: '${temp.path}/docs',
      cachePath: '${temp.path}/cache',
    );
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('JSON writes are atomic and corrupt files read as missing', () async {
    await store.writeJson('library.json', <String, Object?>{'a': 1});
    expect(await store.readJson('library.json'), <String, Object?>{'a': 1});
    expect(File('${store.root.path}/library.json.tmp').existsSync(), isFalse);

    File('${store.root.path}/library.json').writeAsStringSync('{"broken');
    expect(await store.readJson('library.json'), isNull);
    expect(await store.readJson('missing.json'), isNull);
  });

  test('record ids are validated before touching the file system', () {
    expect(() => store.recordDir('../escape'), throwsArgumentError);
    expect(
      store.recordDir('r1700000000-1').path,
      endsWith('records/r1700000000-1'),
    );
  });

  test(
    'exports are cleared on every launch; clearAll empties the store',
    () async {
      final File export = await store.exportFile('x.png');
      await export.writeAsString('png');
      await store.writeJson('settings.json', <String, Object?>{});
      final LocalStore reopened = await LocalStore.open(
        documentsPath: '${temp.path}/docs',
        cachePath: '${temp.path}/cache',
      );
      expect(export.existsSync(), isFalse);
      expect(await reopened.readJson('settings.json'), isNotNull);

      await reopened.clearAll();
      expect(await reopened.readJson('settings.json'), isNull);
      expect(reopened.recordsDir.existsSync(), isTrue);
      expect(reopened.draftDir.existsSync(), isTrue);
    },
  );

  test('settings default safely and persist every change', () async {
    expect(AppSettings.fromJson(null).onboardingDone, isFalse);
    expect(AppSettings.fromJson(null).deleteInputCopies, isTrue);

    final ProviderContainer container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final AppSettingsController controller = container.read(
      appSettingsProvider.notifier,
    );
    await controller.completeOnboarding();
    await controller.setShowGuide(false);
    await controller.setDeleteInputCopies(false);

    final AppSettings reloaded = await AppSettings.load(store);
    expect(reloaded.onboardingDone, isTrue);
    expect(reloaded.showGuide, isFalse);
    expect(reloaded.deleteInputCopies, isFalse);

    await controller.resetKeepingOnboarding();
    final AppSettings reset = await AppSettings.load(store);
    expect(reset.onboardingDone, isTrue);
    expect(reset.showGuide, isTrue);
    expect(reset.deleteInputCopies, isTrue);
  });

  test('device channel results map to honest share/save outcomes', () async {
    const MethodChannel channel = MethodChannel('humantwin/device');
    final List<String> calls = <String>[];
    Map<String, Object?> reply = <String, Object?>{
      'status': 'handedOff',
      'app': '微信',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call.method);
          return reply;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final MethodChannelDeviceServices services = MethodChannelDeviceServices();

    ShareOutcome share = await services.shareFile(
      '/x.png',
      mimeType: 'image/png',
    );
    expect(share.status, ShareStatus.handedOff);
    expect(share.appLabel, '微信');

    reply = <String, Object?>{'status': 'closed'};
    share = await services.shareFile('/x.png', mimeType: 'image/png');
    expect(share.status, ShareStatus.closed);

    reply = <String, Object?>{'status': 'cancelled'};
    expect(
      (await services.saveDocument(
        '/x.glb',
        fileName: 'x.glb',
        mimeType: 'model/gltf-binary',
      )).status,
      SaveStatus.cancelled,
    );
    reply = <String, Object?>{'status': 'unsupported'};
    expect(
      (await services.saveImageToGallery('/x.png', fileName: 'x.png')).status,
      SaveStatus.unsupported,
    );
    expect(calls, <String>[
      'shareFile',
      'shareFile',
      'saveDocument',
      'saveImageToGallery',
    ]);
  });
}
