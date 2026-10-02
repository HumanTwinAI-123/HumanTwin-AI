import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/share/share_controller.dart';
import 'package:human_twin_ai/features/share/share_files.dart';
import 'package:human_twin_ai/features/share/share_preview_screen.dart';
import 'package:human_twin_ai/shared/platform/device_services.dart';

import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled v2 sample (MakeHuman CC0 core assets, shaped in Blender).
  final Uint8List sample = File(
    'assets/models/human_demo.glb',
  ).readAsBytesSync();

  group('GLB labels', () {
    test('the bundled sample keeps its geometry and its own provenance', () {
      final Uint8List labelled = labelGlb(sample, simulated: true);
      final _Glb before = _Glb.parse(sample);
      final _Glb after = _Glb.parse(labelled);

      expect(after.declaredLength, labelled.length);
      expect(after.jsonLength % 4, 0);
      expect(
        after.rest,
        orderedEquals(before.rest),
        reason: 'BIN chunk untouched',
      );
      final Map<String, Object?> asset =
          after.json['asset']! as Map<String, Object?>;
      final Map<String, Object?> label =
          (asset['extras']! as Map<String, Object?>)['humantwin']!
              as Map<String, Object?>;
      expect(label['label'], '示例模型 · 模拟生成');
      expect(label['aiGenerated'], isFalse);
      expect(label['reconstructedFromPhotos'], isFalse);
      expect(label['assetId'], sampleModelAssetId);
      expect(asset['copyright'], contains('MakeHuman'));
      expect(asset['copyright'], contains('CC0'));
      expect(asset['copyright'], isNot(contains('RiggedFigure')));
      expect(asset['version'], '2.0');
      expect(
        after.json['meshes'],
        before.json['meshes'],
        reason: 'only asset metadata changes',
      );
    });

    test('a service model is labelled AI 生成 without sample attribution', () {
      final _Glb after = _Glb.parse(labelGlb(sample, simulated: false));
      final Map<String, Object?> asset =
          after.json['asset']! as Map<String, Object?>;
      expect(
        ((asset['extras']! as Map<String, Object?>)['humantwin']!
            as Map<String, Object?>)['label'],
        'AI 生成 · 仅供展示',
      );
      expect(
        '${asset['copyright']}',
        isNot(contains('HumanTwin AI: metadata')),
      );
    });

    test('non-GLB bytes are rejected', () {
      expect(
        () => labelGlb(
          Uint8List.fromList(utf8.encode('not a model at all!!')),
          simulated: true,
        ),
        throwsFormatException,
      );
    });
  });

  group('PNG', () {
    test('CRC32 matches the PNG reference value', () {
      expect(crc32(ascii.encode('IEND')), 0xAE426082);
    });

    test(
      'the composed image is 1080×1350 with a valid labelled iTXt chunk',
      () async {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 200, 300),
          Paint()..color = const Color(0xFF3355AA),
        );
        final ui.Image snapshot = await recorder.endRecording().toImage(
          200,
          300,
        );

        for (final bool simulated in <bool>[true, false]) {
          final Uint8List png = await composeShareImage(
            snapshot: snapshot,
            snapshotIsLive: true,
            light: false,
            brand: true,
            simulated: simulated,
            attribution: simulated ? modelAttributionFromGlb(sample) : null,
          );
          final List<_Chunk> chunks = _Chunk.parseAll(png);
          expect(chunks.every((_Chunk c) => c.crcValid), isTrue);
          final _Chunk ihdr = chunks.first;
          expect(ihdr.type, 'IHDR');
          expect(ByteData.sublistView(ihdr.data).getUint32(0), 1080);
          expect(ByteData.sublistView(ihdr.data).getUint32(4), 1350);
          final String text = utf8.decode(
            chunks
                .firstWhere((_Chunk c) => c.type == 'iTXt')
                .data
                .skip(16)
                .toList(),
          );
          expect(text, contains(exportLabel(simulated: simulated)));
          expect(text.contains('MakeHuman'), simulated);
          expect(text, isNot(contains('CC BY 4.0')));
        }
        snapshot.dispose();
      },
    );

    test('data URLs from the viewer are parsed, quoted or not', () {
      final String b64 = base64Encode(<int>[1, 2, 3]);
      expect(parseDataUrl('data:image/png;base64,$b64'), <int>[1, 2, 3]);
      expect(parseDataUrl('"data:image/png;base64,$b64"'), <int>[1, 2, 3]);
      expect(parseDataUrl('data:text/html;base64,$b64'), isNull);
      expect(parseDataUrl(42), isNull);
    });
  });

  group('names', () {
    test('names count characters as people see them', () {
      expect(validateRecordName('👩‍👩‍👧‍👦' * 20), isNull);
      expect(validateRecordName('👩‍👩‍👧‍👦' * 21), isNotNull);
      expect(validateRecordName('   '), isNotNull);
    });

    test('export names drop reserved characters and say what the file is', () {
      expect(exportBaseName('a/b:c*?"<>|', simulated: true), 'abc_示例');
      expect(exportBaseName('我的 形象', simulated: false), '我的_形象_AI生成');
      expect(exportBaseName('///', simulated: true), 'HumanTwin_形象_示例');
      final String long = exportBaseName('👍' * 50, simulated: true);
      expect(long, '${'👍' * 40}_示例');
    });
  });

  testWidgets(
    'The 3D file preview exports a labelled copy and reports the share honestly',
    (WidgetTester tester) async {
      configureView(tester, const Size(390, 844));
      final TestApp app = await pumpApp(
        tester,
        records: <GenerationRecord>[doneRecord('rold', name: '晨跑形象')],
        initialLocation: '/avatars/rold/share/file',
      );
      expect(find.byType(SharePreviewScreen), findsOneWidget);
      expect(find.text('晨跑形象_示例.glb'), findsOneWidget);
      expect(find.text('原始照片、位置信息、设备信息'), findsOneWidget);
      await waitFor(
        tester,
        () => find.textContaining('准备中').evaluate().isEmpty,
      );

      await tester.tap(find.text('分享文件…'));
      await waitFor(tester, () => app.device.calls.isNotEmpty);
      expect(app.device.calls, <String>['share model/gltf-binary']);
      expect(find.text('已交给「微信」，请在该应用中完成发送'), findsOneWidget);

      app.device.save = const SaveOutcome(SaveStatus.cancelled);
      await tester.tap(find.text('保存到文件…'));
      await waitFor(tester, () => app.device.calls.length == 2);
      expect(app.device.calls.last, 'saveDocument 晨跑形象_示例.glb');
      await tester.pump();
      expect(find.text('未保存，没有创建任何文件'), findsOneWidget);
    },
  );

  for (final (int sdk, String saveLabel, String call)
      in <(int, String, String)>[
        (34, '保存到相册', 'saveImageToGallery'),
        (28, '保存到文件…', 'saveDocument'),
      ]) {
    testWidgets('The image preview on API $sdk offers 「$saveLabel」', (
      WidgetTester tester,
    ) async {
      configureView(tester, const Size(390, 844));
      final TestApp app = await pumpApp(
        tester,
        sdkInt: sdk,
        records: <GenerationRecord>[doneRecord('rold', name: '晨跑形象')],
        initialLocation: '/avatars/rold/share/image',
      );
      expect(find.text('预览图片'), findsOneWidget);
      await waitFor(tester, () => find.text('正在生成图片…').evaluate().isEmpty);
      expect(find.text(saveLabel), findsOneWidget);
      // A stored render (not a live capture) offers no background choice.
      expect(find.text('浅灰'), findsNothing);

      await tester.tap(find.text(saveLabel));
      await waitFor(tester, () => app.device.calls.isNotEmpty);
      expect(app.device.calls.single, '$call 晨跑形象_示例.png');
    });
  }

  testWidgets('failed regeneration cannot share or save the previous PNG', (
    WidgetTester tester,
  ) async {
    configureView(tester, const Size(390, 844));
    final _FailingRegenerationShareController share =
        _FailingRegenerationShareController();
    final TestApp app = await pumpApp(
      tester,
      records: <GenerationRecord>[doneRecord('rregen')],
      initialLocation: '/avatars/rregen/share/image',
      overrides: [shareControllerProvider.overrideWith(() => share)],
    );
    final Finder shareButton = find.widgetWithText(FilledButton, '分享…');
    final Finder saveButton = find.widgetWithText(OutlinedButton, '保存到相册');
    await waitFor(
      tester,
      () => tester.widget<FilledButton>(shareButton).onPressed != null,
    );
    expect(tester.widget<OutlinedButton>(saveButton).onPressed, isNotNull);

    share.failNextComposition = true;
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await waitFor(tester, () => find.text('图片生成失败').evaluate().isNotEmpty);
    expect(tester.widget<FilledButton>(shareButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(saveButton).onPressed, isNull);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsNothing,
      reason:
          'the old PNG is no longer advertised as the current configuration',
    );
    await tester.tap(shareButton);
    await tester.tap(saveButton);
    expect(app.device.calls, isEmpty);

    // A successful explicit retry prepares a fresh file and enables sharing again.
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await waitFor(
      tester,
      () => tester.widget<FilledButton>(shareButton).onPressed != null,
    );
    expect(tester.widget<OutlinedButton>(saveButton).onPressed, isNotNull);
    await tester.tap(shareButton);
    await waitFor(tester, () => app.device.calls.isNotEmpty);
    expect(app.device.calls, <String>['share image/png']);
  });
}

class _FailingRegenerationShareController extends ShareController {
  bool failNextComposition = false;

  @override
  Future<Uint8List> composeImage(
    GenerationRecord record, {
    required bool light,
    required bool brand,
  }) async {
    if (failNextComposition) {
      failNextComposition = false;
      throw const FileSystemException('Synthetic image composition failure');
    }
    return super.composeImage(record, light: light, brand: brand);
  }
}

class _Glb {
  _Glb(this.declaredLength, this.jsonLength, this.json, this.rest);

  factory _Glb.parse(Uint8List bytes) {
    final ByteData data = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'glTF');
    final int jsonLength = data.getUint32(12, Endian.little);
    return _Glb(
      data.getUint32(8, Endian.little),
      jsonLength,
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)).trimRight())
          as Map<String, Object?>,
      bytes.sublist(20 + jsonLength),
    );
  }

  final int declaredLength;
  final int jsonLength;
  final Map<String, Object?> json;
  final Uint8List rest;
}

class _Chunk {
  _Chunk(this.type, this.data, this.crcValid);

  final String type;
  final Uint8List data;
  final bool crcValid;

  static List<_Chunk> parseAll(Uint8List png) {
    final ByteData view = ByteData.sublistView(png);
    final List<_Chunk> chunks = <_Chunk>[];
    int offset = 8;
    while (offset < png.length) {
      final int length = view.getUint32(offset);
      final Uint8List typeAndData = png.sublist(
        offset + 4,
        offset + 8 + length,
      );
      final int crc = view.getUint32(offset + 8 + length);
      chunks.add(
        _Chunk(
          ascii.decode(typeAndData.sublist(0, 4)),
          typeAndData.sublist(4),
          crc32(typeAndData) == crc,
        ),
      );
      offset += 12 + length;
    }
    return chunks;
  }
}
