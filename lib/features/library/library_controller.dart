import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/storage/local_store.dart';
import '../capture/photo_flow_controller.dart';
import '../generation/digital_twin_repository.dart';
import '../settings/app_settings.dart';
import 'generation_record.dart';

final clockProvider = Provider<DateTime Function()>((Ref ref) => DateTime.now);

/// v1 ships Mock; a developer build pointed at the local proxy uses [GenerationMode.service].
final generationModeProvider = Provider<GenerationMode>(
  (Ref ref) => humanTwinApiBaseUrl.isEmpty
      ? GenerationMode.mock
      : GenerationMode.service,
);

/// Records read before the first frame (overridden at startup).
final initialRecordsProvider = Provider<List<GenerationRecord>>(
  (Ref ref) => const <GenerationRecord>[],
);

/// The latest records, so a rebuilt [LibraryController] never reverts to the startup snapshot.
class _RecordsMemory {
  _RecordsMemory(this.records);

  List<GenerationRecord> records;
}

final _recordsMemoryProvider = Provider<_RecordsMemory>(
  (Ref ref) => _RecordsMemory(ref.watch(initialRecordsProvider)),
);

@immutable
class LibraryState {
  const LibraryState({
    this.records = const <GenerationRecord>[],
    this.missingFiles = const <String>{},
    this.expiredFiles = const <String>{},
    this.redownloading = const <String>{},
  });

  /// Newest first.
  final List<GenerationRecord> records;

  /// Finished records whose local model file is missing or invalid (S15).
  final Set<String> missingFiles;

  /// Missing files the service can no longer provide (S15b).
  final Set<String> expiredFiles;
  final Set<String> redownloading;

  GenerationRecord? byId(String id) {
    for (final GenerationRecord record in records) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  List<GenerationRecord> get avatars =>
      records.where((GenerationRecord r) => r.isDone).toList();

  List<GenerationRecord> get active => records
      .where((GenerationRecord r) => r.info.group == StatusGroup.active)
      .toList();

  List<GenerationRecord> get attention => records
      .where((GenerationRecord r) => r.info.group == StatusGroup.attention)
      .toList();

  /// Unfinished records shown in 我的形象 (not-submitted attempts stay drafts).
  List<GenerationRecord> get libraryTasks => records
      .where((GenerationRecord r) => !r.isDone && r.libraryVisible)
      .toList();

  List<GenerationRecord> get blocking => records
      .where((GenerationRecord r) => blockingStatuses.contains(r.status))
      .toList();

  List<GenerationRecord> get unconfirmed => records
      .where((GenerationRecord r) => unconfirmedStatuses.contains(r.status))
      .toList();

  /// Lights the 我的形象 badge: only items the library actually shows.
  bool get hasLibraryAttention =>
      attention.any((GenerationRecord r) => r.libraryVisible);

  List<GenerationRecord> get justFinished =>
      records.where((GenerationRecord r) => r.isDone && !r.resultSeen).toList();

  LibraryState copyWith({
    List<GenerationRecord>? records,
    Set<String>? missingFiles,
    Set<String>? expiredFiles,
    Set<String>? redownloading,
  }) {
    return LibraryState(
      records: records ?? this.records,
      missingFiles: missingFiles ?? this.missingFiles,
      expiredFiles: expiredFiles ?? this.expiredFiles,
      redownloading: redownloading ?? this.redownloading,
    );
  }
}

/// [storage]: the record could not be saved on this phone, so nothing was started.
enum SubmitBlock { incomplete, busy, unconfirmed, storage }

@immutable
class SubmitResult {
  const SubmitResult.started(String this.id) : block = null;
  const SubmitResult.blocked(SubmitBlock this.block) : id = null;

  final String? id;
  final SubmitBlock? block;
}

/// [busy]: another generation is running, so the check (which may submit) must wait.
enum CheckOutcome {
  bound,
  stillUnknown,
  unresolved,
  nothingCreated,
  busy,
  ignored,
}

enum RedownloadOutcome { restored, expired, failed, ignored }

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

/// Owns generation records and runs them through [DigitalTwinRepository].
///
/// Guarantees (unchanged from the v0.1 controller, now per record):
/// * a provider task is created only by [submit] or the user's explicit [confirmSubmission];
/// * resuming, [continuePolling] and [redownload] only read the task already bound;
/// * a lost create response becomes [RecordStatus.unknown] and is never re-sent automatically;
/// * results of a superseded run are ignored.
class LibraryController extends Notifier<LibraryState> {
  static const String fileName = 'library.json';
  static const int schemaVersion = 1;

  final Map<String, int> _runTokens = <String, int>{};
  Future<void> _writes = Future<void>.value();
  var _sequence = 0;
  var _submitInFlight = false;
  var _resumed = false;
  var _disposed = false;

  @override
  LibraryState build() {
    // Riverpod may reuse this instance on rebuild: reset per-build bookkeeping.
    _resumed = false;
    _disposed = false;
    _runTokens.clear();
    ref.onDispose(() {
      _disposed = true;
      _runTokens.clear();
    });
    final List<GenerationRecord> records = <GenerationRecord>[
      ...ref.read(_recordsMemoryProvider).records,
    ]..sort(_newestFirst);
    return LibraryState(records: records);
  }

  static int _newestFirst(GenerationRecord a, GenerationRecord b) =>
      b.createdAt.compareTo(a.createdAt);

  static Future<List<GenerationRecord>> loadRecords(LocalStore store) async {
    final Map<String, Object?>? json = await store.readJson(fileName);
    final Object? list = json?['records'];
    if (list is! List) {
      return const <GenerationRecord>[];
    }
    final List<GenerationRecord> records = <GenerationRecord>[];
    for (final Object? item in list) {
      try {
        final GenerationRecord? record = GenerationRecord.fromJson(item);
        if (record != null) {
          records.add(record);
        }
      } on Object catch (error) {
        // One damaged entry must not hide the others.
        debugPrint('Skipping unreadable record: $error');
      }
    }
    return records;
  }

  /// False when the index exists but cannot be read; then no files are swept.
  static Future<bool> indexIntact(LocalStore store) async =>
      !await store.file(fileName).exists() ||
      await store.readJson(fileName) != null;

  /// Keeps an unreadable index aside (and its record folders untouched) before the app
  /// writes a new one, so existing records can still be recovered by hand.
  static Future<void> preserveDamagedIndex(LocalStore store) async {
    final File index = store.file(fileName);
    if (await index.exists()) {
      await index.rename(
        '${index.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
  }

  /// Deletes record folders no record refers to (left by an interrupted submission or delete).
  static Future<void> sweepOrphans(
    LocalStore store,
    Iterable<GenerationRecord> records,
  ) async {
    final Set<String> ids = records.map((GenerationRecord r) => r.id).toSet();
    if (!await store.recordsDir.exists()) {
      return;
    }
    await for (final FileSystemEntity entity in store.recordsDir.list()) {
      final String id = entity.path.substring(store.recordsDir.path.length + 1);
      if (entity is Directory && !ids.contains(id)) {
        try {
          await entity.delete(recursive: true);
        } on FileSystemException catch (error) {
          debugPrint('Orphaned record files could not be deleted: $error');
        }
      }
    }
  }

  LocalStore get _store => ref.read(localStoreProvider);
  DigitalTwinRepository get _repository =>
      ref.read(digitalTwinRepositoryProvider);

  GenerationMode get _mode => ref.read(generationModeProvider);

  /// Only records made in this build's mode run here (a Mock build never polls a service task).
  bool _runsHere(GenerationRecord record) => record.mode == _mode;

  Iterable<GenerationRecord> get _blockingHere =>
      state.blocking.where(_runsHere);

  String suggestName() => suggestRecordName(
    state.records.map((GenerationRecord r) => r.name),
    ref.read(generationModeProvider),
    ref.read(clockProvider)(),
  );

  // --------------------------------------------------------------- submit

  /// The single place a new generation starts (the review page's explicit action).
  Future<SubmitResult> submit({
    required String name,
    bool allowWithUnconfirmed = false,
  }) async {
    final PhotoFlowState photos = ref.read(photoFlowControllerProvider);
    if (!photos.isComplete || photos.isPicking) {
      return const SubmitResult.blocked(SubmitBlock.incomplete);
    }
    if (_submitInFlight || _blockingHere.isNotEmpty) {
      return const SubmitResult.blocked(SubmitBlock.busy);
    }
    if (state.unconfirmed.any(_runsHere) && !allowWithUnconfirmed) {
      return const SubmitResult.blocked(SubmitBlock.unconfirmed);
    }
    _submitInFlight = true;
    final String id = _newId();
    try {
      final GenerationRecord pending = GenerationRecord(
        id: id,
        name: name.trim(),
        createdAt: ref.read(clockProvider)(),
        mode: _mode,
        status: RecordStatus.submitting,
      );
      await ref
          .read(photoFlowControllerProvider.notifier)
          .handOff(
            Directory('${_store.recordDir(id).path}/inputs'),
            commit: (List<String> inputs) async {
              state = state.copyWith(
                records: <GenerationRecord>[
                  pending.copyWith(inputs: inputs),
                  ...state.records,
                ],
              );
              try {
                // Write-ahead: if the app dies before the reply, the record becomes 待确认,
                // never a silent resubmission. Nothing starts unless this write succeeds.
                await _persist(strict: true);
              } on Object {
                _drop(id);
                rethrow;
              }
            },
          );
    } on Object catch (error) {
      debugPrint('Submission could not be stored: $error');
      _drop(id);
      try {
        await _store.deleteRecordDir(id);
      } on Object {
        // Swept on next launch.
      }
      return const SubmitResult.blocked(SubmitBlock.storage);
    } finally {
      _submitInFlight = false;
    }
    unawaited(_runCreate(id, _bump(id)));
    return SubmitResult.started(id);
  }

  void _drop(String id) {
    if (state.byId(id) != null) {
      state = state.copyWith(
        records: state.records
            .where((GenerationRecord r) => r.id != id)
            .toList(),
      );
    }
  }

  Future<void> _runCreate(String id, int token) async {
    final GenerationRecord? record = state.byId(id);
    if (record == null) {
      return;
    }
    if (record.inputs.length != 3) {
      // Nothing can be sent without the photos (a service record stays 待确认 to be safe).
      await _setStatus(
        id,
        record.mode == GenerationMode.mock
            ? RecordStatus.failed
            : RecordStatus.unknown,
      );
      return;
    }
    final GenerationTask task;
    try {
      task = await _repository.createTask(
        front: XFile(_absolute(record.inputs[0])),
        side: XFile(_absolute(record.inputs[1])),
        back: XFile(_absolute(record.inputs[2])),
      );
    } on GenerationException catch (error) {
      if (_isCurrent(id, token)) {
        await _setStatus(
          id,
          _createFailure(error.kind),
          failureKind: error.kind,
        );
      }
      return;
    } on Object {
      if (_isCurrent(id, token)) {
        // A request may have left the device: never resend it automatically.
        await _setStatus(
          id,
          record.mode == GenerationMode.mock
              ? RecordStatus.failed
              : RecordStatus.unknown,
        );
      }
      return;
    }
    if (!_isCurrent(id, token)) {
      return;
    }
    _replace(
      id,
      (GenerationRecord r) => r.copyWith(
        taskId: task.id,
        origin: task.origin,
        status: RecordStatus.processing,
        progress: null,
        failureKind: null,
      ),
    );
    await _persist();
    await _runFetch(id, token);
  }

  /// Polls and downloads the bound task (GET only).
  Future<void> _runFetch(String id, int token) async {
    final GenerationRecord? record = state.byId(id);
    final String? taskId = record?.taskId;
    if (record == null || taskId == null) {
      return;
    }
    final GenerationTask task = GenerationTask(
      id: taskId,
      origin: record.origin ?? ModelOrigin.simulatedSample,
    );
    final DigitalTwinModel model;
    try {
      model = await _repository.fetchModel(
        task,
        onProgress: (int progress) {
          if (!_isCurrent(id, token)) {
            return;
          }
          final GenerationRecord? current = state.byId(id);
          if (current != null &&
              (current.status == RecordStatus.processing ||
                  current.status == RecordStatus.queued)) {
            _replace(
              id,
              (GenerationRecord r) => r.copyWith(
                status: progress >= 100
                    ? RecordStatus.saving
                    : RecordStatus.processing,
                progress: progress.clamp(0, 100),
              ),
            );
          }
        },
      );
    } on GenerationException catch (error) {
      if (_isCurrent(id, token)) {
        await _setStatus(
          id,
          _fetchFailure(error.kind),
          failureKind: error.kind,
        );
      }
      return;
    } on Object {
      if (_isCurrent(id, token)) {
        await _setStatus(id, RecordStatus.failed);
      }
      return;
    }
    if (!_isCurrent(id, token)) {
      return;
    }
    _replace(
      id,
      (GenerationRecord r) =>
          r.copyWith(status: RecordStatus.saving, progress: 100),
    );
    await _storeModel(id, model, token);
  }

  Future<void> _storeModel(String id, DigitalTwinModel model, int token) async {
    ModelRef? modelRef;
    int? bytes;
    try {
      if (model.src.startsWith('file://')) {
        final File source = File(Uri.parse(model.src).toFilePath());
        final File target = File('${_store.recordDir(id).path}/model.glb');
        await target.parent.create(recursive: true);
        await source.copy(target.path);
        modelRef = ModelRef.file(_store.relative(target.path));
        bytes = await target.length();
      } else {
        modelRef = ModelRef.asset(model.src);
        bytes = await _assetLength(model.src);
      }
    } on Object {
      if (_isCurrent(id, token)) {
        await _setStatus(
          id,
          RecordStatus.downloadFailed,
          failureKind: GenerationFailureKind.downloadFailed,
        );
      }
      return;
    }
    if (!_isCurrent(id, token)) {
      await _deleteIfRemoved(id);
      return;
    }
    final bool deleteInputs = ref.read(appSettingsProvider).deleteInputCopies;
    if (deleteInputs) {
      await _deleteInputs(id);
    }
    _replace(
      id,
      (GenerationRecord r) => r.copyWith(
        status: RecordStatus.done,
        progress: 100,
        model: modelRef,
        modelBytes: bytes,
        origin: model.origin,
        inputs: deleteInputs ? const <String>[] : r.inputs,
        resultSeen: false,
        failureKind: null,
      ),
    );
    await _persist();
  }

  Future<int?> _assetLength(String key) async {
    try {
      return (await rootBundle.load(key)).lengthInBytes;
    } on Object {
      return null;
    }
  }

  static RecordStatus _createFailure(GenerationFailureKind kind) {
    return switch (kind) {
      GenerationFailureKind.invalidPhotos ||
      GenerationFailureKind.photosRejected => RecordStatus.rejected,
      GenerationFailureKind.serviceUnavailable => RecordStatus.offline,
      GenerationFailureKind.serviceRejected => RecordStatus.config,
      GenerationFailureKind.submissionUnknown => RecordStatus.unknown,
      GenerationFailureKind.submissionUnresolved => RecordStatus.unresolved,
      _ => RecordStatus.unknown,
    };
  }

  static RecordStatus _fetchFailure(GenerationFailureKind kind) {
    return switch (kind) {
      GenerationFailureKind.pollingTimedOut => RecordStatus.timeout,
      GenerationFailureKind.statusUnavailable ||
      GenerationFailureKind.serviceUnavailable ||
      GenerationFailureKind.serviceRejected => RecordStatus.connection,
      GenerationFailureKind.downloadFailed => RecordStatus.downloadFailed,
      _ => RecordStatus.failed,
    };
  }

  // ------------------------------------------------------------- recovery

  /// 继续查询 / 重新下载: reads the same task again (GET only).
  Future<void> continuePolling(String id) async {
    final GenerationRecord? record = state.byId(id);
    const Set<RecordStatus> resumable = <RecordStatus>{
      RecordStatus.timeout,
      RecordStatus.paused,
      RecordStatus.connection,
      RecordStatus.downloadFailed,
    };
    if (record == null ||
        record.taskId == null ||
        !_runsHere(record) ||
        !resumable.contains(record.status)) {
      return;
    }
    final int token = _bump(id);
    _replace(
      id,
      (GenerationRecord r) => r.copyWith(
        status: r.status == RecordStatus.downloadFailed
            ? RecordStatus.saving
            : RecordStatus.processing,
        failureKind: null,
      ),
    );
    await _persist();
    await _runFetch(id, token);
  }

  /// 停止查询进度: stops reading; the provider task keeps running. Returns whether it stopped.
  Future<bool> stopPolling(String id) async {
    final GenerationRecord? record = state.byId(id);
    if (record == null ||
        record.mode != GenerationMode.service ||
        (record.status != RecordStatus.queued &&
            record.status != RecordStatus.processing)) {
      return false;
    }
    _bump(id);
    await _setStatus(id, RecordStatus.paused);
    return true;
  }

  /// 确认提交状态: re-sends the identical photos once; the relay de-duplicates by content.
  Future<CheckOutcome> confirmSubmission(String id) async {
    final GenerationRecord? record = state.byId(id);
    if (record == null ||
        !_runsHere(record) ||
        !unconfirmedStatuses.contains(record.status) ||
        record.inputs.length != 3) {
      return CheckOutcome.ignored;
    }
    if (_submitInFlight || _blockingHere.isNotEmpty) {
      // A check may submit: keep to one active generation.
      return CheckOutcome.busy;
    }
    final int token = _bump(id);
    // An inconclusive check never downgrades 需人工确认 back to 待确认.
    final RecordStatus unsettled = record.status;
    await _setStatus(id, RecordStatus.checking);
    final GenerationTask task;
    try {
      task = await _repository.createTask(
        front: XFile(_absolute(record.inputs[0])),
        side: XFile(_absolute(record.inputs[1])),
        back: XFile(_absolute(record.inputs[2])),
      );
    } on GenerationException catch (error) {
      if (!_isCurrent(id, token)) {
        return CheckOutcome.ignored;
      }
      // Only an explicit refusal by the service proves the earlier submission created
      // nothing; an error before or during sending leaves it 待确认.
      final RecordStatus next = switch (error.kind) {
        GenerationFailureKind.submissionUnresolved => RecordStatus.unresolved,
        GenerationFailureKind.photosRejected => RecordStatus.rejected,
        GenerationFailureKind.serviceRejected => RecordStatus.config,
        _ => unsettled,
      };
      await _setStatus(id, next, failureKind: error.kind);
      return switch (next) {
        RecordStatus.unknown => CheckOutcome.stillUnknown,
        RecordStatus.unresolved => CheckOutcome.unresolved,
        _ => CheckOutcome.nothingCreated,
      };
    } on Object {
      if (_isCurrent(id, token)) {
        await _setStatus(id, unsettled);
      }
      return unsettled == RecordStatus.unresolved
          ? CheckOutcome.unresolved
          : CheckOutcome.stillUnknown;
    }
    if (!_isCurrent(id, token)) {
      return CheckOutcome.ignored;
    }
    _replace(
      id,
      (GenerationRecord r) => r.copyWith(
        taskId: task.id,
        origin: task.origin,
        status: RecordStatus.processing,
        recovered: true,
        failureKind: null,
      ),
    );
    await _persist();
    unawaited(_runFetch(id, token));
    return CheckOutcome.bound;
  }

  /// Copies a record's photos back into the editable draft (保存为草稿, 用新照片重新生成).
  ///
  /// A non-empty draft is replaced only with [replaceExisting]. The record is removed only
  /// once the draft holds the photos, and never while a submission is unconfirmed or in flight.
  Future<DraftRestore> restoreToDraft(
    String id, {
    Set<PhotoAngle> leaveEmpty = const <PhotoAngle>{},
    bool keepRecord = false,
    bool replaceExisting = false,
  }) async {
    final GenerationRecord? record = state.byId(id);
    if (record == null || record.inputs.length != 3) {
      return DraftRestore.unavailable;
    }
    final DraftRestore result = await ref
        .read(photoFlowControllerProvider.notifier)
        .restoreDraft(
          <PhotoAngle, String>{
            PhotoAngle.front: _absolute(record.inputs[0]),
            PhotoAngle.side: _absolute(record.inputs[1]),
            PhotoAngle.back: _absolute(record.inputs[2]),
          },
          leaveEmpty: leaveEmpty,
          replaceExisting: replaceExisting,
        );
    final bool mustKeep =
        unconfirmedStatuses.contains(record.status) ||
        _removalLocked.contains(record.status);
    if (result == DraftRestore.restored && !keepRecord && !mustKeep) {
      await removeRecord(id);
    }
    return result;
  }

  /// A request may be leaving the device: the record cannot be removed until it settles.
  static const Set<RecordStatus> _removalLocked = <RecordStatus>{
    RecordStatus.submitting,
    RecordStatus.checking,
  };

  // ------------------------------------------------------------ manage

  Future<void> rename(String id, String name) async {
    if (validateRecordName(name) != null || state.byId(id) == null) {
      return;
    }
    _replace(id, (GenerationRecord r) => r.copyWith(name: name.trim()));
    await _persist();
  }

  Future<void> markSeen(String id) async {
    final GenerationRecord? record = state.byId(id);
    if (record == null || record.resultSeen || !record.isDone) {
      return;
    }
    _replace(id, (GenerationRecord r) => r.copyWith(resultSeen: true));
    await _persist();
  }

  /// Removes the record, its photo copies and model from this phone (provider data untouched).
  /// Returns false while a submission is in flight.
  Future<bool> removeRecord(String id) async {
    final GenerationRecord? record = state.byId(id);
    if (record != null && _removalLocked.contains(record.status)) {
      return false;
    }
    _bump(id);
    _runTokens.remove(id);
    state = state.copyWith(
      records: state.records.where((GenerationRecord r) => r.id != id).toList(),
      missingFiles: <String>{...state.missingFiles}..remove(id),
      expiredFiles: <String>{...state.expiredFiles}..remove(id),
    );
    await _persist();
    try {
      await _store.deleteRecordDir(id);
    } on Object catch (error) {
      debugPrint('Record files could not be deleted: $error');
    }
    return true;
  }

  /// 清除全部本机数据.
  Future<void> clearAll() async {
    for (final String id in _runTokens.keys.toList()) {
      _bump(id);
    }
    _runTokens.clear();
    state = const LibraryState();
    await ref.read(photoFlowControllerProvider.notifier).reset();
    await _writes;
    await _store.clearAll();
    await ref.read(appSettingsProvider.notifier).resetKeepingOnboarding();
    await _persist();
  }

  /// 重新下载 for a finished record whose local file is missing (GET of the same task).
  Future<RedownloadOutcome> redownload(String id) async {
    final GenerationRecord? record = state.byId(id);
    if (record == null ||
        !_runsHere(record) ||
        !state.missingFiles.contains(id) ||
        state.redownloading.contains(id) ||
        record.taskId == null) {
      return RedownloadOutcome.ignored;
    }
    state = state.copyWith(redownloading: <String>{...state.redownloading, id});
    try {
      final DigitalTwinModel model = await _repository.fetchModel(
        GenerationTask(
          id: record.taskId!,
          origin: record.origin ?? ModelOrigin.serviceGenerated,
        ),
      );
      final File source = File(Uri.parse(model.src).toFilePath());
      final File target = File('${_store.recordDir(id).path}/model.glb');
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      if (_disposed || state.byId(id) == null) {
        // Deleted while downloading: do not leave the file behind.
        await _deleteIfRemoved(id);
        return RedownloadOutcome.ignored;
      }
      state = state.copyWith(
        missingFiles: <String>{...state.missingFiles}..remove(id),
        redownloading: <String>{...state.redownloading}..remove(id),
      );
      return RedownloadOutcome.restored;
    } on GenerationException catch (error) {
      if (_disposed) {
        return RedownloadOutcome.ignored;
      }
      final bool gone = error.kind == GenerationFailureKind.taskFailed;
      state = state.copyWith(
        redownloading: <String>{...state.redownloading}..remove(id),
        expiredFiles: gone
            ? <String>{...state.expiredFiles, id}
            : state.expiredFiles,
      );
      return gone ? RedownloadOutcome.expired : RedownloadOutcome.failed;
    } on Object {
      if (_disposed) {
        return RedownloadOutcome.ignored;
      }
      state = state.copyWith(
        redownloading: <String>{...state.redownloading}..remove(id),
      );
      return RedownloadOutcome.failed;
    }
  }

  // ------------------------------------------------------------- resume

  /// Called once after launch: applies the restart rules and checks stored model files.
  Future<void> resumeInterrupted() async {
    if (_resumed) {
      return;
    }
    _resumed = true;
    bool changed = false;
    for (final GenerationRecord record in state.records.toList()) {
      final bool mock = record.mode == GenerationMode.mock;
      if (!_runsHere(record)) {
        // Made by a build in the other mode: never run it here, only settle its state.
        final RecordStatus? settled = switch (record.status) {
          RecordStatus.submitting || RecordStatus.checking =>
            mock ? RecordStatus.failed : RecordStatus.unknown,
          RecordStatus.queued ||
          RecordStatus.processing ||
          RecordStatus.saving =>
            mock
                ? RecordStatus.failed
                : (record.taskId == null
                      ? RecordStatus.unknown
                      : RecordStatus.paused),
          _ => null,
        };
        if (settled != null) {
          _replace(
            record.id,
            (GenerationRecord r) => r.copyWith(status: settled, progress: null),
          );
          changed = true;
        }
        continue;
      }
      switch (record.status) {
        case RecordStatus.submitting:
          if (mock) {
            // A local simulation creates nothing remotely; it simply restarts.
            unawaited(_runCreate(record.id, _bump(record.id)));
          } else {
            _replace(
              record.id,
              (GenerationRecord r) => r.copyWith(status: RecordStatus.unknown),
            );
            changed = true;
          }
        case RecordStatus.checking:
          _replace(
            record.id,
            (GenerationRecord r) => r.copyWith(status: RecordStatus.unknown),
          );
          changed = true;
        case RecordStatus.queued ||
            RecordStatus.processing ||
            RecordStatus.saving:
          if (record.taskId != null) {
            unawaited(_runFetch(record.id, _bump(record.id)));
          } else if (mock) {
            unawaited(_runCreate(record.id, _bump(record.id)));
          } else {
            _replace(
              record.id,
              (GenerationRecord r) => r.copyWith(status: RecordStatus.unknown),
            );
            changed = true;
          }
        case RecordStatus.done:
          final ModelRef? model = record.model;
          if (model != null &&
              !model.isAsset &&
              !await _isValidGlb(model.value)) {
            state = state.copyWith(
              missingFiles: <String>{...state.missingFiles, record.id},
            );
          }
        default:
          break;
      }
    }
    if (changed) {
      await _persist();
    }
  }

  Future<bool> _isValidGlb(String relativePath) async {
    try {
      final File file = _store.file(relativePath);
      final int length = await file.length();
      if (length < 12) {
        return false;
      }
      final RandomAccessFile handle = await file.open();
      try {
        final List<int> header = await handle.read(4);
        return String.fromCharCodes(header) == 'glTF';
      } finally {
        await handle.close();
      }
    } on Object {
      return false;
    }
  }

  // ------------------------------------------------------------ helpers

  int _bump(String id) => _runTokens[id] = (_runTokens[id] ?? 0) + 1;

  bool _isCurrent(String id, int token) =>
      !_disposed && _runTokens[id] == token && state.byId(id) != null;

  /// After an await: if the record was removed meanwhile, delete files written for it.
  Future<void> _deleteIfRemoved(String id) async {
    if (_disposed || state.byId(id) != null) {
      return;
    }
    try {
      await _store.deleteRecordDir(id);
    } on Object catch (error) {
      debugPrint('Record files could not be deleted: $error');
    }
  }

  String _newId() {
    final int micros = ref.read(clockProvider)().microsecondsSinceEpoch;
    return 'r${micros.toRadixString(36)}${(_sequence++).toRadixString(36)}';
  }

  String _absolute(String path) =>
      path.startsWith('/') ? path : _store.file(path).path;

  void _replace(String id, GenerationRecord Function(GenerationRecord) change) {
    state = state.copyWith(
      records: <GenerationRecord>[
        for (final GenerationRecord record in state.records)
          record.id == id ? change(record) : record,
      ],
    );
  }

  Future<void> _setStatus(
    String id,
    RecordStatus status, {
    GenerationFailureKind? failureKind,
  }) async {
    _replace(
      id,
      (GenerationRecord r) =>
          r.copyWith(status: status, failureKind: failureKind),
    );
    await _persist();
  }

  Future<void> _deleteInputs(String id) async {
    try {
      await _store.deleteRecordFiles(id, 'inputs');
    } on Object catch (error) {
      debugPrint('Photo copies could not be deleted: $error');
    }
  }

  /// Serialised, atomic writes of the whole index. With [strict] a failed write is rethrown
  /// to the caller (the chain itself always continues).
  Future<void> _persist({bool strict = false}) {
    ref.read(_recordsMemoryProvider).records = state.records;
    final Map<String, Object?> json = <String, Object?>{
      'schemaVersion': schemaVersion,
      'records': <Object?>[
        for (final GenerationRecord record in state.records) record.toJson(),
      ],
    };
    Object? failure;
    StackTrace? trace;
    final Future<void> write = _writes.then((_) async {
      try {
        await _store.writeJson(fileName, json);
      } on Object catch (error, stack) {
        debugPrint('Library could not be saved: $error');
        failure = error;
        trace = stack;
      }
    });
    _writes = write;
    if (!strict) {
      return write;
    }
    return write.then((_) {
      final Object? error = failure;
      if (error != null) {
        Error.throwWithStackTrace(error, trace ?? StackTrace.current);
      }
    });
  }
}
