import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/share/share_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'current sample export retains its source and geometry while adding labels',
    () {
      final Uint8List original = _glb(<String, Object?>{
        'asset': _currentAsset,
      });
      final Uint8List labelled = labelGlb(original, simulated: true);
      final Map<String, Object?> asset = _asset(labelled);
      final Map<String, Object?> extras =
          asset['extras'] as Map<String, Object?>;
      final Map<String, Object?> origin =
          extras['humantwin'] as Map<String, Object?>;

      expect(origin['assetId'], sampleModelAssetId);
      expect(origin['source'], sampleModelSource);
      expect(origin['createdDate'], '2026-10-01');
      expect(origin['license'], 'CC0-1.0');
      expect(
        origin['baseSource'],
        'https://github.com/makehumancommunity/makehuman',
      );
      expect(origin['reconstructedFromPhotos'], isFalse);
      expect(origin['aiGenerated'], isFalse);
      expect(extras['retainedField'], 'keep');
      expect(asset['copyright'], contains(sampleModelCopyright));
      expect(asset['copyright'], isNot(contains('RiggedFigure')));
      expect(_binaryTail(labelled), _binaryTail(original));
      // Re-exporting must neither lose provenance nor duplicate attribution.
      expect(
        _asset(labelGlb(labelled, simulated: true))['copyright'],
        asset['copyright'],
      );
    },
  );

  test('v1 local sample keeps original provenance after a v2 bundle update', () {
    const String copyright =
        'HumanTwin AI original procedural demonstration avatar. Created in Blender; '
        'no imported third-party model geometry.';
    final Uint8List original = _glb(<String, Object?>{
      'asset': <String, Object?>{
        'version': '2.0',
        'copyright': copyright,
        'extras': <String, Object?>{
          'humantwin': <String, Object?>{
            'assetId': 'humantwin-avatar-v1',
            'source': 'original-blender-procedural',
            'createdDate': '2026-10-01',
          },
        },
      },
    });
    final Uint8List labelled = labelGlb(original, simulated: true);
    final Map<String, Object?> asset = _asset(labelled);
    final Map<String, Object?> extras = asset['extras'] as Map<String, Object?>;
    final Map<String, Object?> origin =
        extras['humantwin'] as Map<String, Object?>;
    expect(origin['assetId'], 'humantwin-avatar-v1');
    expect(origin['source'], 'original-blender-procedural');
    expect(asset['copyright'], contains(copyright));
    expect(asset['copyright'], isNot(contains('MakeHuman')));
    expect(modelAttributionFromGlb(labelled).label, contains('原创示例模型'));
    expect(_binaryTail(labelled), _binaryTail(original));
  });

  test('legacy fake downloads retain CC BY attribution on re-export', () {
    final Uint8List original = _legacyGlb();
    final Uint8List labelled = labelGlb(original, simulated: true);
    final Map<String, Object?> asset = _asset(labelled);
    expect(asset['copyright'], contains('© 2017 Cesium'));
    expect(asset['copyright'], contains('CC BY 4.0'));
    expect(asset['copyright'], isNot(contains('original procedural')));
    expect(_binaryTail(labelled), _binaryTail(original));
    expect(modelAttributionFromGlb(labelled).label, contains('RiggedFigure'));
  });

  test(
    'unknown sample retains its own provenance without an original claim',
    () {
      const String copyright = 'Example Author · example license';
      final Uint8List original = _glb(<String, Object?>{
        'asset': <String, Object?>{
          'version': '2.0',
          'copyright': copyright,
          'extras': <String, Object?>{
            'humantwin': <String, Object?>{
              'assetId': 'another-model',
              'source': 'another-author',
            },
          },
        },
      });
      final Uint8List labelled = labelGlb(original, simulated: true);
      final Map<String, Object?> asset = _asset(labelled);
      final Map<String, Object?> extras =
          asset['extras'] as Map<String, Object?>;
      final Map<String, Object?> origin =
          extras['humantwin'] as Map<String, Object?>;
      expect(origin['assetId'], 'another-model');
      expect(origin['source'], 'another-author');
      expect(asset['copyright'], contains(copyright));
      expect(asset['copyright'], isNot(contains(sampleModelCopyright)));
      expect(modelAttributionFromGlb(original).label, isNot(contains('原创')));
    },
  );

  test('service export keeps provider copyright and source metadata', () {
    final Uint8List original = _glb(<String, Object?>{
      'asset': <String, Object?>{
        'version': '2.0',
        'copyright': 'Provider copyright',
        'extras': <String, Object?>{
          'humantwin': <String, Object?>{
            'source': 'test-provider',
            'provider': 'Original provider',
          },
        },
      },
    });
    final Map<String, Object?> asset = _asset(
      labelGlb(original, simulated: false),
    );
    final Map<String, Object?> extras = asset['extras'] as Map<String, Object?>;
    final Map<String, Object?> origin =
        extras['humantwin'] as Map<String, Object?>;
    expect(asset['copyright'], 'Provider copyright');
    expect(origin['source'], 'test-provider');
    expect(origin['provider'], 'Original provider');
    expect(origin['exportedBy'], 'HumanTwin AI');
    expect(origin['aiGenerated'], isTrue);
  });

  for (final bool legacy in <bool>[false, true]) {
    test(
      'PNG metadata follows ${legacy ? 'legacy' : 'current'} model',
      () async {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
        final ui.Image snapshot = await recorder.endRecording().toImage(4, 4);
        try {
          final Uint8List model = legacy
              ? _legacyGlb()
              : _glb(<String, Object?>{'asset': _currentAsset});
          final Uint8List png = await composeShareImage(
            snapshot: snapshot,
            snapshotIsLive: true,
            light: false,
            brand: false,
            simulated: true,
            attribution: modelAttributionFromGlb(model),
          );
          final String metadata = utf8.decode(png, allowMalformed: true);
          expect(metadata, contains('示例模型 · 模拟生成'));
          expect(
            metadata,
            contains(legacy ? 'CC BY 4.0' : sampleModelCopyright),
          );
          expect(
            metadata,
            isNot(contains(legacy ? sampleModelCopyright : 'RiggedFigure')),
          );
        } finally {
          snapshot.dispose();
        }
      },
    );
  }
}

const Map<String, Object?> _currentAsset = <String, Object?>{
  'version': '2.0',
  'copyright': sampleModelCopyright,
  'extras': <String, Object?>{
    'retainedField': 'keep',
    'humantwin': <String, Object?>{
      'assetId': sampleModelAssetId,
      'source': sampleModelSource,
      'license': 'CC0-1.0',
      'baseSource': 'https://github.com/makehumancommunity/makehuman',
      'reconstructedFromPhotos': false,
      'createdDate': '2026-10-01',
    },
  },
};

Uint8List _legacyGlb() => _glb(<String, Object?>{
  'asset': <String, Object?>{'version': '2.0', 'generator': 'COLLADA2GLTF'},
  'nodes': <Map<String, Object?>>[
    for (final String name in <String>[
      'Z_UP',
      'Proxy',
      'torso_joint_1',
      'arm_joint_R_1',
      'leg_joint_L_1',
    ])
      <String, Object?>{'name': name},
  ],
});

Uint8List _glb(Map<String, Object?> json) {
  final Uint8List encoded = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  final int padded = (encoded.length + 3) & ~3;
  final Uint8List result = Uint8List(20 + padded + 12);
  final ByteData header = ByteData.sublistView(result);
  result.setRange(0, 4, ascii.encode('glTF'));
  header
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, result.length, Endian.little)
    ..setUint32(12, padded, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little)
    ..setUint32(20 + padded, 4, Endian.little)
    ..setUint32(24 + padded, 0x004E4942, Endian.little);
  result
    ..setRange(20, 20 + encoded.length, encoded)
    ..fillRange(20 + encoded.length, 20 + padded, 0x20)
    ..setRange(28 + padded, 32 + padded, <int>[1, 2, 3, 4]);
  return result;
}

Map<String, Object?> _asset(Uint8List glb) {
  final int length = ByteData.sublistView(glb).getUint32(12, Endian.little);
  final Map<String, Object?> json =
      jsonDecode(utf8.decode(glb.sublist(20, 20 + length)))
          as Map<String, Object?>;
  return json['asset'] as Map<String, Object?>;
}

Uint8List _binaryTail(Uint8List glb) {
  final int length = ByteData.sublistView(glb).getUint32(12, Endian.little);
  return glb.sublist(20 + length);
}
