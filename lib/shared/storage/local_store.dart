import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-private, persistent storage for the local v1 (no cloud, no database).
///
/// ```text
/// <documents>/humantwin/
///   settings.json              app settings
///   library.json               generation records (atomic writes)
///   records/<id>/              per-record files (photo copies, models, thumbnails)
///   drafts/current/            PhotoFlowController's persisted draft photos
/// <cache>/exports/             files prepared for sharing (cleared on launch)
/// ```
class LocalStore {
  LocalStore({required this.root, required this.exportsDir});

  static int _tempSequence = 0;

  final Directory root;
  final Directory exportsDir;

  static Future<LocalStore> open({
    required String documentsPath,
    required String cachePath,
  }) async {
    final LocalStore store = LocalStore(
      root: Directory('$documentsPath/humantwin'),
      exportsDir: Directory('$cachePath/exports'),
    );
    await store.root.create(recursive: true);
    await store.recordsDir.create(recursive: true);
    await store.draftDir.create(recursive: true);
    // Exports are transient copies made for one share/save; never kept across launches.
    if (await store.exportsDir.exists()) {
      await store.exportsDir.delete(recursive: true);
    }
    await store.exportsDir.create(recursive: true);
    return store;
  }

  Directory get recordsDir => Directory('${root.path}/records');
  Directory get draftDir => Directory('${root.path}/drafts/current');

  Directory recordDir(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'invalid record id');
    }
    return Directory('${recordsDir.path}/$id');
  }

  File file(String relativePath) => File('${root.path}/$relativePath');

  /// Path of [absolute] relative to [root] (stored paths survive app-container moves).
  String relative(String absolute) {
    final String prefix = '${root.path}/';
    return absolute.startsWith(prefix)
        ? absolute.substring(prefix.length)
        : absolute;
  }

  Future<Map<String, Object?>?> readJson(String name) async {
    final File target = file(name);
    try {
      if (!await target.exists()) {
        return null;
      }
      final Object? decoded = jsonDecode(await target.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      // A corrupt file is treated as missing rather than crashing the app.
      return null;
    }
  }

  /// Writes JSON atomically: a crash mid-write never leaves a truncated file.
  Future<void> writeJson(String name, Map<String, Object?> json) async {
    final File target = file(name);
    // Unique per write, so two writers never share (or rename away) the same temp file.
    final File temp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${_tempSequence++}.tmp',
    );
    try {
      await temp.writeAsString(jsonEncode(json), flush: true);
      await temp.rename(target.path);
    } on Object {
      try {
        await temp.delete();
      } on FileSystemException {
        // Never created.
      }
      rethrow;
    }
  }

  Future<void> deleteRecordDir(String id) async {
    final Directory dir = recordDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Deletes one sub-folder of a record (e.g. its `inputs` photo copies).
  Future<void> deleteRecordFiles(String id, String folder) async {
    final Directory dir = Directory('${recordDir(id).path}/$folder');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Removes every record, draft, setting and prepared export (「清除全部本机数据」).
  ///
  /// [root] itself is kept: on iOS it carries the "excluded from backup" flag, which a
  /// recreated folder would not have.
  Future<void> clearAll() async {
    await _deleteContents(root);
    await _deleteContents(exportsDir);
    await root.create(recursive: true);
    await exportsDir.create(recursive: true);
    await recordsDir.create(recursive: true);
    await draftDir.create(recursive: true);
  }

  static Future<void> _deleteContents(Directory dir) async {
    if (!await dir.exists()) {
      return;
    }
    await for (final FileSystemEntity entity in dir.list()) {
      await entity.delete(recursive: true);
    }
  }

  /// Fresh export file path (cache), sanitised and unique.
  Future<File> exportFile(String fileName) async {
    await exportsDir.create(recursive: true);
    final Directory dir = await exportsDir.createTemp('x');
    return File('${dir.path}/$fileName');
  }

  /// Total bytes stored under [root].
  Future<int> usedBytes() async {
    int total = 0;
    if (!await root.exists()) {
      return 0;
    }
    await for (final FileSystemEntity entity in root.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // Ignore files removed during the scan.
        }
      }
    }
    return total;
  }
}

/// Overridden at startup with the opened store.
final localStoreProvider = Provider<LocalStore>(
  (Ref ref) => throw StateError('LocalStore must be provided at startup'),
);
