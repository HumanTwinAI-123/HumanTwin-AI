import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/storage/local_store.dart';
import '../generation/digital_twin_repository.dart';
import '../library/generation_record.dart';
import '../library/record_widgets.dart';
import '../viewer/digital_twin_viewer.dart';
import 'share_files.dart';

@immutable
class Snapshot {
  const Snapshot(this.bytes, {required this.live});

  final Uint8List bytes;

  /// Captured from the current 3D view (vs. the stored fixed-angle render).
  final bool live;
}

@immutable
class ShareState {
  const ShareState({this.snapshots = const <String, Snapshot>{}});

  final Map<String, Snapshot> snapshots;
}

/// A file prepared for one share/save: exactly the bytes the preview shows.
@immutable
class PreparedExport {
  const PreparedExport({
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final File file;
  final String fileName;
  final String mimeType;
  final int bytes;
}

final shareControllerProvider = NotifierProvider<ShareController, ShareState>(
  ShareController.new,
);

class ShareController extends Notifier<ShareState> {
  // The pinned model-viewer bundle renders each scene at its own scaleStep.
  // Its public toDataURL exposes the whole shared canvas, while public toBlob
  // uses the renderer's global scale, which can differ from a static scene's.
  // Use the bundle's actual sceneSize/displayCanvas pair, guarded for fallback.
  // WebView's synchronous JS result API does not await promises: poll FileReader's
  // completed string instead, and keep late callbacks scoped to their request.
  static const String _captureScript = r'''
(() => {
  const captureId = __CAPTURE_ID__;
  const capture = {id: captureId, result: '', error: false};
  window.__humanTwinSnapshot = capture;
  const viewer = document.querySelector('model-viewer');
  if (!viewer) {
    capture.error = true;
    return;
  }
  const current = () => window.__humanTwinSnapshot === capture;
  try {
    const symbolValue = name => {
      for (let p = viewer; p; p = Object.getPrototypeOf(p)) {
        const key = Object.getOwnPropertySymbols(p).find(s => s.description === name);
        if (key) return viewer[key];
      }
      return null;
    };
    const scene = symbolValue('scene');
    const renderer = symbolValue('renderer');
    if (!scene || !renderer || typeof renderer.sceneSize !== 'function' ||
        typeof renderer.displayCanvas !== 'function') {
      capture.error = true;
      return;
    }
    const viewport = renderer.sceneSize(scene);
    const source = renderer.displayCanvas(scene);
    if (!source || !viewport ||
        !Number.isFinite(viewport.width) || !Number.isFinite(viewport.height) ||
        !(viewport.width > 0 && viewport.height > 0) ||
        viewport.width > source.width || viewport.height > source.height) {
      capture.error = true;
      return;
    }
    const output = document.createElement('canvas');
    output.width = viewport.width;
    output.height = viewport.height;
    const context = output.getContext('2d');
    if (!context) {
      capture.error = true;
      return;
    }
    context.drawImage(source, 0, 0, viewport.width, viewport.height,
        0, 0, viewport.width, viewport.height);
    output.toBlob(blob => {
      if (!current()) return;
      if (!blob) {
        capture.error = true;
        return;
      }
      const reader = new FileReader();
      reader.onload = () => {
        if (current()) capture.result = reader.result;
      };
      reader.onerror = () => {
        if (current()) capture.error = true;
      };
      reader.readAsDataURL(blob);
    }, 'image/png');
  } catch (_) {
    if (current()) capture.error = true;
  }
})();
''';
  static const Duration _captureTimeout = Duration(seconds: 5);
  int _captureSequence = 0;

  /// Export copies written per record, deleted with the avatar (else cleared at next launch).
  final Map<String, List<File>> _exports = <String, List<File>>{};

  @override
  ShareState build() => const ShareState();

  /// Takes a snapshot of the current view; falls back to the stored render of the model.
  Future<void> captureSnapshot(
    GenerationRecord record, {
    ViewerScripts? scripts,
  }) async {
    Snapshot? snapshot;
    if (scripts != null) {
      try {
        final Uint8List bytes = await _captureLiveSnapshot(scripts);
        snapshot = Snapshot(bytes, live: true);
      } on Object catch (error) {
        debugPrint('Viewer snapshot unavailable: $error');
      }
    }
    snapshot ??= await _storedRender(record);
    if (snapshot != null) {
      state = ShareState(
        snapshots: <String, Snapshot>{...state.snapshots, record.id: snapshot},
      );
    }
  }

  Future<Uint8List> _captureLiveSnapshot(ViewerScripts scripts) async {
    final String id = jsonEncode(
      '${DateTime.now().microsecondsSinceEpoch}-${_captureSequence++}',
    );
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      await scripts
          .run(_captureScript.replaceAll('__CAPTURE_ID__', id))
          .timeout(_captureTimeout);
      while (elapsed.elapsed < _captureTimeout) {
        final Object result = await scripts
            .evaluate(
              "(() => { const c = window.__humanTwinSnapshot; "
              "return c && c.id === $id ? "
              "(c.error ? 'snapshot-error' : c.result) : ''; })();",
            )
            .timeout(_captureTimeout - elapsed.elapsed);
        final Uint8List? bytes = parseDataUrl(result);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
        if (result is String && result.contains('snapshot-error')) {
          throw StateError('Viewer snapshot capture failed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      throw TimeoutException('Viewer snapshot capture timed out');
    } finally {
      try {
        await scripts
            .run(
              "if (window.__humanTwinSnapshot && "
              "window.__humanTwinSnapshot.id === $id) "
              "delete window.__humanTwinSnapshot;",
            )
            .timeout(const Duration(milliseconds: 500));
      } on Object {
        // A page that exited cannot retain a live capture; fallback still works.
      }
    }
  }

  Future<Snapshot?> _storedRender(GenerationRecord record) async {
    try {
      if (record.isSimulated &&
          record.model?.isAsset == true &&
          record.model?.value == sampleModelAsset) {
        // The sample's stored render (same model; fixed viewing angle).
        final ByteData data = await rootBundle.load(sampleThumbnailAsset);
        return Snapshot(data.buffer.asUint8List(), live: false);
      }
      final File thumb = ref
          .read(localStoreProvider)
          .file('records/${record.id}/thumb.png');
      if (await thumb.exists()) {
        return Snapshot(await thumb.readAsBytes(), live: false);
      }
    } on Object catch (error) {
      debugPrint('Stored render unavailable: $error');
    }
    return null;
  }

  Snapshot? snapshotFor(String id) => state.snapshots[id];

  /// Composes the PNG exactly as it will be sent.
  Future<Uint8List> composeImage(
    GenerationRecord record, {
    required bool light,
    required bool brand,
  }) async {
    final Snapshot snapshot =
        state.snapshots[record.id] ??
        await _storedRender(record) ??
        (throw StateError('No snapshot'));
    final ModelAttribution? attribution = record.isSimulated
        ? modelAttributionFromGlb(await _modelBytes(record))
        : null;
    final ui.Image image = await decodeImage(snapshot.bytes);
    final ui.Image? mark = brand ? await _mark() : null;
    try {
      return await composeShareImage(
        snapshot: image,
        snapshotIsLive: snapshot.live,
        light: light && snapshot.live,
        brand: brand,
        simulated: record.isSimulated,
        attribution: attribution,
        mark: mark,
      );
    } finally {
      image.dispose();
      mark?.dispose();
    }
  }

  Future<ui.Image?> _mark() async {
    try {
      final ByteData data = await rootBundle.load(
        'assets/images/brand/humantwin_mark.png',
      );
      return decodeImage(data.buffer.asUint8List());
    } on Object {
      return null;
    }
  }

  Future<PreparedExport> writeImage(
    GenerationRecord record,
    Uint8List png,
  ) async {
    final String name =
        '${exportBaseName(record.name, simulated: record.isSimulated)}.png';
    final File file = await _exportFile(record, name);
    await file.writeAsBytes(png, flush: true);
    return PreparedExport(
      file: file,
      fileName: name,
      mimeType: 'image/png',
      bytes: png.length,
    );
  }

  /// A labelled copy of the stored GLB (geometry unchanged).
  Future<PreparedExport> prepareModel(GenerationRecord record) async {
    final Uint8List original = await _modelBytes(record);
    final Uint8List labelled = labelGlb(
      original,
      simulated: record.isSimulated,
    );
    final String name =
        '${exportBaseName(record.name, simulated: record.isSimulated)}.glb';
    final File file = await _exportFile(record, name);
    await file.writeAsBytes(labelled, flush: true);
    return PreparedExport(
      file: file,
      fileName: name,
      mimeType: 'model/gltf-binary',
      bytes: labelled.length,
    );
  }

  Future<Uint8List> _modelBytes(GenerationRecord record) async {
    final ModelRef? model = record.model;
    if (model == null) {
      throw StateError('Record has no model');
    }
    return model.isAsset
        ? (await rootBundle.load(model.value)).buffer.asUint8List()
        : await ref.read(localStoreProvider).file(model.value).readAsBytes();
  }

  Future<File> _exportFile(GenerationRecord record, String name) async {
    final File file = await ref.read(localStoreProvider).exportFile(name);
    (_exports[record.id] ??= <File>[]).add(file);
    return file;
  }

  /// A deleted avatar: drops its snapshot and deletes the export copies made from it.
  void forget(String id) {
    if (state.snapshots.containsKey(id)) {
      state = ShareState(
        snapshots: <String, Snapshot>{...state.snapshots}..remove(id),
      );
    }
    final List<File>? files = _exports.remove(id);
    if (files != null) {
      unawaited(_deleteExports(files));
    }
  }

  static Future<void> _deleteExports(List<File> files) async {
    for (final File file in files) {
      try {
        // Each export has its own folder under the exports cache.
        await file.parent.delete(recursive: true);
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  /// After 清除全部本机数据 (the store has already emptied the exports folder).
  void clear() {
    _exports.clear();
    state = const ShareState();
  }
}
