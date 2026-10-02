import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../generation/digital_twin_repository.dart';

/// Attribution for earlier RiggedFigure downloads, which remain valid local records.
const String legacySampleAttribution =
    'RiggedFigure © 2017 Cesium; Cesium for Everything. CC BY 4.0 '
    '(https://creativecommons.org/licenses/by/4.0/). Source: KhronosGroup/glTF-Sample-Assets. '
    'Modified by HumanTwin AI: metadata labels added; geometry and textures unchanged.';

const String _exportModification =
    'Modified by HumanTwin AI: metadata labels added; geometry and textures unchanged.';

const String _proceduralV1Copyright =
    'HumanTwin AI original procedural demonstration avatar. Created in Blender; '
    'no imported third-party model geometry.';

class ModelAttribution {
  const ModelAttribution({required this.label, required this.metadata});

  final String label;
  final String metadata;
}

const ModelAttribution _unknownSampleAttribution = ModelAttribution(
  label: '示例模型 · 来源见文件信息',
  metadata:
      'Sample demonstration model; origin follows the input GLB metadata.',
);

/// Uses the actual GLB, because older local fake results may still be RiggedFigure.
ModelAttribution modelAttributionFromGlb(Uint8List glb) {
  final Map<String, Object?> json = _glbJson(glb);
  final Map<String, Object?> asset = Map<String, Object?>.from(
    json['asset'] as Map,
  );
  final Object? extras = asset['extras'];
  final Object? origin = extras is Map ? extras['humantwin'] : null;
  final String copyright = asset['copyright'] is String
      ? asset['copyright'] as String
      : '';
  if (origin is Map &&
      origin['assetId'] == sampleModelAssetId &&
      origin['source'] == sampleModelSource) {
    return ModelAttribution(
      label: sampleModelAttribution,
      metadata: copyright.isEmpty ? sampleModelCopyright : copyright,
    );
  }
  // Historical local results keep their own identity when the bundled sample changes.
  if (origin is Map &&
      origin['assetId'] == 'humantwin-avatar-v1' &&
      origin['source'] == 'original-blender-procedural') {
    return ModelAttribution(
      label: 'HumanTwin AI 原创示例模型 · Blender',
      metadata: copyright.isEmpty ? _proceduralV1Copyright : copyright,
    );
  }
  // The original Khronos asset has no copyright field. Identify its stable node
  // signature as well as exports that already carry the attribution.
  final Object? nodes = json['nodes'];
  final Set<Object?> names = nodes is List
      ? nodes.whereType<Map>().map((Map n) => n['name']).toSet()
      : <Object?>{};
  final bool riggedFigure =
      copyright.contains('RiggedFigure') ||
      (asset['generator'] == 'COLLADA2GLTF' &&
          names.containsAll(<String>[
            'Z_UP',
            'Proxy',
            'torso_joint_1',
            'arm_joint_R_1',
            'leg_joint_L_1',
          ]));
  if (riggedFigure) {
    return ModelAttribution(
      label: '示例模型：Khronos RiggedFigure · CC BY 4.0',
      metadata: copyright.contains('CC BY 4.0')
          ? copyright
          : copyright.isEmpty
          ? legacySampleAttribution
          : '$copyright | $legacySampleAttribution',
    );
  }
  return ModelAttribution(
    label: _unknownSampleAttribution.label,
    metadata: copyright.isEmpty
        ? _unknownSampleAttribution.metadata
        : copyright,
  );
}

/// The fixed, non-removable honesty label on exports.
String exportLabel({required bool simulated}) =>
    simulated ? '示例模型 · 模拟生成' : 'AI 生成 · 仅供展示';

// ------------------------------------------------------------------- GLB

Map<String, Object?> _glbJson(Uint8List glb) {
  final ByteData data = ByteData.sublistView(glb);
  if (glb.length < 20 ||
      String.fromCharCodes(glb.sublist(0, 4)) != 'glTF' ||
      data.getUint32(4, Endian.little) != 2 ||
      data.getUint32(8, Endian.little) != glb.length) {
    throw const FormatException('Not a glTF 2.0 binary');
  }
  final int jsonLength = data.getUint32(12, Endian.little);
  final int jsonType = data.getUint32(16, Endian.little);
  if (jsonType != 0x4E4F534A || 20 + jsonLength > glb.length) {
    throw const FormatException('Missing JSON chunk');
  }
  return jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, Object?>;
}

/// Adds export labels while retaining provenance, copyright and all binary chunks.
Uint8List labelGlb(Uint8List glb, {required bool simulated}) {
  final Map<String, Object?> json = _glbJson(glb);
  final int jsonLength = ByteData.sublistView(glb).getUint32(12, Endian.little);
  final Map<String, Object?> asset = Map<String, Object?>.from(
    (json['asset'] as Map<String, Object?>?) ??
        <String, Object?>{'version': '2.0'},
  );
  final Map<String, Object?> extras = Map<String, Object?>.from(
    (asset['extras'] as Map<String, Object?>?) ?? <String, Object?>{},
  );
  final Object? existingOrigin = extras['humantwin'];
  extras['humantwin'] = <String, Object?>{
    if (existingOrigin is Map) ...Map<String, Object?>.from(existingOrigin),
    'label': exportLabel(simulated: simulated),
    'aiGenerated': !simulated,
    'origin': simulated ? 'simulatedSample' : 'serviceGenerated',
    if (existingOrigin is! Map || !existingOrigin.containsKey('provider'))
      'provider': 'HumanTwin AI',
    'exportedBy': 'HumanTwin AI',
    if (simulated) 'reconstructedFromPhotos': false,
    'exportModification':
        'metadata labels added; geometry and textures unchanged',
  };
  asset['extras'] = extras;
  if (simulated) {
    final String attribution = modelAttributionFromGlb(glb).metadata;
    asset['copyright'] = attribution.contains(_exportModification)
        ? attribution
        : '$attribution | $_exportModification';
  }
  json['asset'] = asset;

  final List<int> encoded = utf8.encode(jsonEncode(json));
  final int padded = (encoded.length + 3) & ~3;
  final Uint8List jsonChunk = Uint8List(padded)
    ..setAll(0, encoded)
    ..fillRange(encoded.length, padded, 0x20);
  final Uint8List rest = glb.sublist(20 + jsonLength);
  final int total = 12 + 8 + padded + rest.length;
  final BytesBuilder out = BytesBuilder(copy: false);
  final ByteData header = ByteData(20)
    ..setUint8(0, 0x67)
    ..setUint8(1, 0x6C)
    ..setUint8(2, 0x54)
    ..setUint8(3, 0x46)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, total, Endian.little)
    ..setUint32(12, padded, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  out
    ..add(header.buffer.asUint8List())
    ..add(jsonChunk)
    ..add(rest);
  return out.toBytes();
}

// ------------------------------------------------------------------- PNG

/// Inserts an iTXt (UTF-8) chunk after IHDR so the label also lives in the file metadata.
Uint8List addPngText(Uint8List png, String keyword, String text) {
  const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  for (int i = 0; i < signature.length; i++) {
    if (png[i] != signature[i]) {
      throw const FormatException('Not a PNG');
    }
  }
  final int ihdrLength = ByteData.sublistView(png).getUint32(8, Endian.big);
  final int insertAt = 8 + 12 + ihdrLength;
  final List<int> body = <int>[
    ...latin1.encode(keyword),
    0, // keyword terminator
    0, // not compressed
    0, // compression method
    0, // empty language tag
    0, // empty translated keyword
    ...utf8.encode(text),
  ];
  final List<int> type = ascii.encode('iTXt');
  final ByteData length = ByteData(4)..setUint32(0, body.length, Endian.big);
  final ByteData crc = ByteData(4)
    ..setUint32(0, crc32(<int>[...type, ...body]), Endian.big);
  return Uint8List.fromList(<int>[
    ...png.sublist(0, insertAt),
    ...length.buffer.asUint8List(),
    ...type,
    ...body,
    ...crc.buffer.asUint8List(),
    ...png.sublist(insertAt),
  ]);
}

final List<int> _crcTable = List<int>.generate(256, (int n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> bytes) {
  int c = 0xFFFFFFFF;
  for (final int b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ------------------------------------------------------------ composition

/// 1080×1350 share image: model snapshot, caption band with the fixed label, optional brand,
/// and (for a sample) its actual model-source attribution.
Future<Uint8List> composeShareImage({
  required ui.Image snapshot,
  required bool snapshotIsLive,
  required bool light,
  required bool brand,
  required bool simulated,
  ModelAttribution? attribution,
  ui.Image? mark,
}) async {
  const double width = 1080;
  const double height = 1350;
  const double band = height * 0.13;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect full = const Offset(0, 0) & const Size(width, height);
  canvas.drawRect(
    full,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(width / 2, height * 0.42),
        width * 0.95,
        light
            ? const <Color>[
                Color(0xFFDFE5EC),
                Color(0xFFB9C3CF),
                Color(0xFF9BA7B5),
              ]
            : const <Color>[
                Color(0xFF1D2939),
                Color(0xFF121821),
                Color(0xFF0F141B),
              ],
        const <double>[0, 0.55, 1],
      ),
  );

  final Rect stage = Rect.fromLTWH(0, 0, width, height - band);
  final Size image = Size(
    snapshot.width.toDouble(),
    snapshot.height.toDouble(),
  );
  // A live capture is fitted inside the stage; a stored render already has its own framing.
  final FittedSizes fitted = applyBoxFit(
    snapshotIsLive ? BoxFit.contain : BoxFit.cover,
    image,
    snapshotIsLive ? stage.deflate(48).size : stage.size,
  );
  final Rect source = Alignment.center.inscribe(
    fitted.source,
    Offset.zero & image,
  );
  final Rect target = Alignment.center.inscribe(
    fitted.destination,
    snapshotIsLive ? stage.deflate(48) : stage,
  );
  canvas.drawImageRect(
    snapshot,
    source,
    target,
    Paint()..filterQuality = FilterQuality.high,
  );

  final Color ink = light ? const Color(0xFF0D1117) : const Color(0xFFF2F5F8);
  if (simulated) {
    _paintText(
      canvas,
      (attribution ?? _unknownSampleAttribution).label,
      Offset(48, height - band - 52),
      size: 27,
      color: ink.withValues(alpha: 0.6),
    );
  }
  final Rect bandRect = Rect.fromLTWH(0, height - band, width, band);
  canvas.drawRect(
    bandRect,
    Paint()..color = light ? const Color(0x8CFFFFFF) : const Color(0x8C080B0F),
  );
  canvas.drawLine(
    bandRect.topLeft,
    bandRect.topRight,
    Paint()
      ..color = (light ? const Color(0xFF0D1117) : const Color(0xFFF2F5F8))
          .withValues(alpha: 0.08)
      ..strokeWidth = 2,
  );

  final String label =
      '${simulated ? '▣' : '✦'} ${exportLabel(simulated: simulated)}';
  final ui.Paragraph labelText = _paragraph(
    label,
    size: 36,
    weight: FontWeight.w600,
    color: simulated
        ? (light ? const Color(0xFF4B3BB5) : const Color(0xFFE3DCFF))
        : (light ? const Color(0xFF075A70) : const Color(0xFFB8F6FF)),
  );
  final double pillHeight = labelText.height + 36;
  final RRect pill = RRect.fromRectAndRadius(
    Rect.fromLTWH(
      48,
      bandRect.center.dy - pillHeight / 2,
      labelText.maxIntrinsicWidth + 60,
      pillHeight,
    ),
    Radius.circular(pillHeight / 2),
  );
  canvas.drawRRect(
    pill,
    Paint()
      ..color = simulated
          ? const Color(0xFF7B61FF).withValues(alpha: light ? 0.14 : 0.28)
          : const Color(0xFF00E5FF).withValues(alpha: light ? 0.12 : 0.2),
  );
  canvas.drawParagraph(labelText, Offset(pill.left + 30, pill.top + 18));

  if (brand) {
    final ui.Paragraph wordmark = _paragraph(
      'HumanTwin AI',
      size: 36,
      weight: FontWeight.w600,
      color: ink,
    );
    final double right = width - 48;
    final double textLeft = right - wordmark.maxIntrinsicWidth;
    canvas.drawParagraph(
      wordmark,
      Offset(textLeft, bandRect.center.dy - wordmark.height / 2),
    );
    final ui.Image? markImage = mark;
    if (markImage != null) {
      const double markSize = 60;
      canvas.drawImageRect(
        markImage,
        Offset.zero &
            Size(markImage.width.toDouble(), markImage.height.toDouble()),
        Rect.fromLTWH(
          textLeft - markSize - 14,
          bandRect.center.dy - markSize / 2,
          markSize,
          markSize,
        ),
        Paint()..filterQuality = FilterQuality.high,
      );
    }
  }

  final ui.Image composed = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final ByteData? bytes = await composed.toByteData(
    format: ui.ImageByteFormat.png,
  );
  composed.dispose();
  final Uint8List png = bytes!.buffer.asUint8List();
  return addPngText(
    png,
    'Description',
    'HumanTwin AI · ${exportLabel(simulated: simulated)}${simulated ? ' · ${(attribution ?? _unknownSampleAttribution).metadata}' : ''}',
  );
}

ui.Paragraph _paragraph(
  String text, {
  required double size,
  FontWeight weight = FontWeight.w400,
  required Color color,
}) {
  final ui.ParagraphBuilder builder =
      ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
        ..pushStyle(
          ui.TextStyle(color: color, fontSize: size, fontWeight: weight),
        )
        ..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 1000));
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset, {
  required double size,
  required Color color,
}) {
  canvas.drawParagraph(_paragraph(text, size: size, color: color), offset);
}

/// Decodes PNG/JPEG bytes into an image.
Future<ui.Image> decodeImage(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

/// Parses a `data:image/png;base64,…` result returned by the WebView (possibly JSON-quoted).
Uint8List? parseDataUrl(Object? result) {
  if (result is! String) {
    return null;
  }
  String value = result.trim();
  if (value.startsWith('"') && value.endsWith('"')) {
    try {
      value = jsonDecode(value) as String;
    } on FormatException {
      value = value.substring(1, value.length - 1);
    }
  }
  final int comma = value.indexOf(',');
  if (!value.startsWith('data:image/png;base64') || comma < 0) {
    return null;
  }
  try {
    return base64Decode(value.substring(comma + 1));
  } on FormatException {
    return null;
  }
}
