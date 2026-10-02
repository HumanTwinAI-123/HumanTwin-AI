import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/share/share_controller.dart';
import 'package:human_twin_ai/features/viewer/digital_twin_viewer.dart';

import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capture waits for cropped PNG bytes instead of a JS promise', () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final ShareController share = container.read(
      shareControllerProvider.notifier,
    );
    final Uint8List png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE9kAAAAASUVORK5CYII=',
    );
    final String url = 'data:image/png;base64,${base64Encode(png)}';
    int polls = 0;
    bool started = false;
    bool cleaned = false;
    final ViewerScripts scripts = ViewerScripts(
      run: (String script) async {
        if (script.contains('renderer.sceneSize(scene)')) {
          started = true;
        } else if (script.contains('delete window.__humanTwinSnapshot')) {
          cleaned = true;
        }
      },
      evaluate: (String script) async {
        if (!started) throw StateError('No asynchronous capture was started');
        return ++polls < 3 ? '' : jsonEncode(url);
      },
    );
    await share.captureSnapshot(doneRecord('rcrop'), scripts: scripts);
    final Snapshot? snapshot = share.snapshotFor('rcrop');
    expect(snapshot, isNotNull);
    expect(snapshot!.live, isTrue);
    expect(snapshot.bytes, orderedEquals(png));
    expect(polls, 3);
    expect(cleaned, isTrue);
  });

  test(
    'failed blob capture cleans up and falls back to the stored render',
    () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ShareController share = container.read(
        shareControllerProvider.notifier,
      );
      bool cleaned = false;
      final ViewerScripts scripts = ViewerScripts(
        run: (String script) async {
          if (script.contains('delete window.__humanTwinSnapshot')) {
            cleaned = true;
          }
        },
        evaluate: (String script) async => 'snapshot-error',
      );
      await share.captureSnapshot(doneRecord('rfallback'), scripts: scripts);
      final Snapshot? snapshot = share.snapshotFor('rfallback');
      expect(snapshot, isNotNull);
      expect(snapshot!.live, isFalse);
      expect(snapshot.bytes, isNotEmpty);
      expect(cleaned, isTrue);
    },
  );
}
