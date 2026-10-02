import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/storage/local_store.dart';

enum PhotoAngle { front, side, back }

@immutable
class PhotoFlowState {
  const PhotoFlowState({
    this.front,
    this.side,
    this.back,
    this.pendingAngle,
    this.errorAngle,
    this.errorMessage,
  });

  static const Object _notProvided = Object();

  final XFile? front;
  final XFile? side;
  final XFile? back;
  final PhotoAngle? pendingAngle;
  final PhotoAngle? errorAngle;
  final String? errorMessage;

  bool get isComplete => front != null && side != null && back != null;

  bool get isPicking => pendingAngle != null;

  bool get isEmpty => front == null && side == null && back == null;

  int get count =>
      (front == null ? 0 : 1) + (side == null ? 0 : 1) + (back == null ? 0 : 1);

  XFile? photoFor(PhotoAngle angle) {
    return switch (angle) {
      PhotoAngle.front => front,
      PhotoAngle.side => side,
      PhotoAngle.back => back,
    };
  }

  String? errorFor(PhotoAngle angle) {
    return errorAngle == angle ? errorMessage : null;
  }

  PhotoFlowState copyWith({
    Object? front = _notProvided,
    Object? side = _notProvided,
    Object? back = _notProvided,
    Object? pendingAngle = _notProvided,
    Object? errorAngle = _notProvided,
    Object? errorMessage = _notProvided,
  }) {
    return PhotoFlowState(
      front: identical(front, _notProvided) ? this.front : front as XFile?,
      side: identical(side, _notProvided) ? this.side : side as XFile?,
      back: identical(back, _notProvided) ? this.back : back as XFile?,
      pendingAngle: identical(pendingAngle, _notProvided)
          ? this.pendingAngle
          : pendingAngle as PhotoAngle?,
      errorAngle: identical(errorAngle, _notProvided)
          ? this.errorAngle
          : errorAngle as PhotoAngle?,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

/// A picked file that cannot be used; [message] is shown to the user.
class PhotoRejected implements Exception {
  const PhotoRejected(this.message);

  final String message;

  @override
  String toString() => 'PhotoRejected($message)';
}

/// Persistence for the editable draft. [PhotoFlowController] stays the only owner of
/// draft photos; the store only keeps its files on disk and validates new picks.
abstract class DraftPhotoStore {
  /// Draft photos saved by a previous session.
  Future<Map<PhotoAngle, XFile>> load();

  /// Validates [picked] and returns the draft's own copy of it.
  Future<XFile> adopt(PhotoAngle angle, XFile picked);

  /// Deletes a draft copy that is no longer used.
  Future<void> release(XFile photo);

  /// Records which draft copies belong to which angle (and an angle being picked, so a
  /// photo recovered after Android ends the app during picking goes back to that angle).
  Future<void> persist(PhotoFlowState state);

  /// The angle that was being picked when the app last stopped, if any.
  Future<PhotoAngle?> pickingAngle();

  /// Copies the complete draft into [targetDir] (front/side/back) and returns their paths.
  /// The draft itself is untouched; a failed copy leaves no partial files behind.
  Future<List<String>> copyTo(PhotoFlowState state, Directory targetDir);

  /// Copies a submitted photo back into the draft (e.g. after 保存为草稿).
  Future<XFile> restore(PhotoAngle angle, String sourcePath);

  /// Whether a draft photo's file still exists (e.g. before 撤销 puts it back).
  bool isAvailable(XFile photo);
}

/// No persistence or validation (tests and non-file environments).
class PassthroughDraftPhotoStore implements DraftPhotoStore {
  const PassthroughDraftPhotoStore();

  @override
  Future<Map<PhotoAngle, XFile>> load() async => const <PhotoAngle, XFile>{};

  @override
  Future<XFile> adopt(PhotoAngle angle, XFile picked) async => picked;

  @override
  Future<void> release(XFile photo) async {}

  @override
  Future<void> persist(PhotoFlowState state) async {}

  @override
  Future<PhotoAngle?> pickingAngle() async => null;

  @override
  Future<List<String>> copyTo(PhotoFlowState state, Directory targetDir) async {
    return <String>[
      for (final PhotoAngle angle in PhotoAngle.values)
        state.photoFor(angle)!.path,
    ];
  }

  @override
  Future<XFile> restore(PhotoAngle angle, String sourcePath) async =>
      XFile(sourcePath);

  @override
  bool isAvailable(XFile photo) => true;
}

/// File-backed draft in `<store>/drafts/current`, with picker-cache cleanup.
class FileDraftPhotoStore implements DraftPhotoStore {
  FileDraftPhotoStore(
    this.store, {
    required this.strictFormats,
    this.cacheRoot,
  });

  static const String manifestName = 'drafts/current/draft.json';
  static const int strictMaxBytes = 8 * 1024 * 1024;
  static const int lenientMaxBytes = 40 * 1024 * 1024;

  final LocalStore store;

  /// Upload builds accept only JPEG/PNG ≤ 8 MB (the service limit); Mock accepts any common photo.
  final bool Function() strictFormats;

  /// The app cache; picker copies found there are deleted once adopted.
  final String? cacheRoot;

  Directory get _dir => store.draftDir;

  @override
  Future<Map<PhotoAngle, XFile>> load() async {
    final Map<String, Object?>? manifest = await store.readJson(manifestName);
    final Map<PhotoAngle, XFile> photos = <PhotoAngle, XFile>{};
    if (manifest == null) {
      return photos;
    }
    for (final PhotoAngle angle in PhotoAngle.values) {
      final Object? name = manifest[angle.name];
      if (name is String && !name.contains('/')) {
        final File file = File('${_dir.path}/$name');
        if (await file.exists()) {
          photos[angle] = XFile(file.path);
        }
      }
    }
    return photos;
  }

  @override
  Future<XFile> adopt(PhotoAngle angle, XFile picked) async {
    final File source = File(picked.path);
    final int length;
    final List<int> header;
    try {
      length = await source.length();
      final RandomAccessFile handle = await source.open();
      try {
        header = await handle.read(16);
      } finally {
        await handle.close();
      }
    } on Object {
      throw const PhotoRejected('照片无法读取，请重新选择。');
    }
    try {
      return await _validateAndCopy(angle, source, length, header);
    } on PhotoRejected {
      // A rejected pick is not kept either.
      await _purgePickerCopy(source);
      rethrow;
    }
  }

  Future<XFile> _validateAndCopy(
    PhotoAngle angle,
    File source,
    int length,
    List<int> header,
  ) async {
    final String? extension = _photoExtension(header);
    final bool strict = strictFormats();
    if (length == 0 || extension == null) {
      throw PhotoRejected(
        strict
            ? '文件格式不受支持。请选择 JPEG 或 PNG 格式、单张不超过 8 MB 的照片。'
            : '这个文件不是可用的照片，请重新选择。',
      );
    }
    if (strict &&
        (length > strictMaxBytes ||
            (extension != 'jpg' && extension != 'png'))) {
      throw const PhotoRejected('文件格式不受支持。请选择 JPEG 或 PNG 格式、单张不超过 8 MB 的照片。');
    }
    if (length > lenientMaxBytes) {
      throw const PhotoRejected('照片文件过大，请选择其他照片。');
    }
    await _dir.create(recursive: true);
    final File copy = File(
      '${_dir.path}/${angle.name}-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await source.copy(copy.path);
    await _purgePickerCopy(source);
    return XFile(copy.path);
  }

  @override
  Future<void> release(XFile photo) async {
    final File file = File(photo.path);
    if (_isInDraft(file.path) && await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> persist(PhotoFlowState state) async {
    await store.writeJson(manifestName, <String, Object?>{
      for (final PhotoAngle angle in PhotoAngle.values)
        angle.name: _draftName(state.photoFor(angle)),
      'picking': state.pendingAngle?.name,
    });
  }

  @override
  Future<PhotoAngle?> pickingAngle() async {
    final Object? name = (await store.readJson(manifestName))?['picking'];
    for (final PhotoAngle angle in PhotoAngle.values) {
      if (angle.name == name) {
        return angle;
      }
    }
    return null;
  }

  @override
  Future<List<String>> copyTo(PhotoFlowState state, Directory targetDir) async {
    final List<File> copied = <File>[];
    try {
      await targetDir.create(recursive: true);
      for (final PhotoAngle angle in PhotoAngle.values) {
        final File source = File(state.photoFor(angle)!.path);
        final String extension = source.path.split('.').last;
        copied.add(
          await source.copy('${targetDir.path}/${angle.name}.$extension'),
        );
      }
    } on Object {
      for (final File file in copied) {
        try {
          await file.delete();
        } on FileSystemException {
          // Already gone.
        }
      }
      rethrow;
    }
    return <String>[for (final File file in copied) store.relative(file.path)];
  }

  /// Deletes draft files the manifest no longer references (left by an interrupted write).
  /// Call only when the manifest was read successfully.
  Future<void> sweep() async {
    if (!await _dir.exists()) {
      return;
    }
    final Map<String, Object?>? manifest = await store.readJson(manifestName);
    final Set<Object?> kept = <Object?>{...?manifest?.values, 'draft.json'};
    await for (final FileSystemEntity entity in _dir.list()) {
      final String name = entity.path.substring(_dir.path.length + 1);
      if (entity is File && !kept.contains(name)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Best effort.
        }
      }
    }
  }

  /// False when a manifest exists but cannot be read (then nothing is swept).
  Future<bool> manifestIntact() async =>
      !await store.file(manifestName).exists() ||
      await store.readJson(manifestName) != null;

  @override
  Future<XFile> restore(PhotoAngle angle, String sourcePath) async {
    final File source = File(sourcePath);
    final String extension = sourcePath.split('.').last;
    await _dir.create(recursive: true);
    final File copy = File(
      '${_dir.path}/${angle.name}-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await source.copy(copy.path);
    return XFile(copy.path);
  }

  @override
  bool isAvailable(XFile photo) => File(photo.path).existsSync();

  bool _isInDraft(String path) => path.startsWith('${_dir.path}/');

  String? _draftName(XFile? photo) {
    if (photo == null || !_isInDraft(photo.path)) {
      return null;
    }
    return photo.path.substring(_dir.path.length + 1);
  }

  Future<void> _purgePickerCopy(File source) async {
    String? cache = cacheRoot;
    while (cache != null && cache.length > 1 && cache.endsWith('/')) {
      cache = cache.substring(0, cache.length - 1);
    }
    // Only the picker's own cache copies; never a gallery original.
    if (cache == null || !source.path.startsWith('$cache/')) {
      return;
    }
    try {
      await source.delete();
    } on FileSystemException {
      // Best effort: the OS clears the cache eventually.
    }
  }

  static String? _photoExtension(List<int> h) {
    if (h.length >= 3 && h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) {
      return 'jpg';
    }
    const List<int> png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (h.length >= png.length &&
        Iterable<int>.generate(png.length).every((int i) => h[i] == png[i])) {
      return 'png';
    }
    if (h.length >= 12 &&
        String.fromCharCodes(h.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(h.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    if (h.length >= 12 && String.fromCharCodes(h.sublist(4, 8)) == 'ftyp') {
      final String brand = String.fromCharCodes(h.sublist(8, 12));
      if (<String>{
        'heic',
        'heix',
        'hevc',
        'heim',
        'heis',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return 'heic';
      }
    }
    return null;
  }
}

final imagePickerProvider = Provider<ImagePicker>((Ref ref) => ImagePicker());

final draftPhotoStoreProvider = Provider<DraftPhotoStore>(
  (Ref ref) => const PassthroughDraftPhotoStore(),
);

/// Draft photos loaded before the first frame (overridden at startup).
final initialDraftProvider = Provider<Map<PhotoAngle, XFile>>(
  (Ref ref) => const <PhotoAngle, XFile>{},
);

/// The angle being picked when the app last stopped (overridden at startup).
final initialPickingAngleProvider = Provider<PhotoAngle?>((Ref ref) => null);

/// What [PhotoFlowController.restoreDraft] did.
enum DraftRestore { restored, draftNotEmpty, unavailable, failed }

final lostDataRecoverySupportedProvider = Provider<bool>(
  (Ref ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

final photoFlowControllerProvider =
    NotifierProvider<PhotoFlowController, PhotoFlowState>(
      PhotoFlowController.new,
    );

/// The only owner of the editable front/side/back draft photos.
class PhotoFlowController extends Notifier<PhotoFlowState> {
  late ImagePicker _picker;
  late DraftPhotoStore _drafts;
  var _operationGeneration = 0;
  Future<void>? _lostDataRecovery;
  Future<void> _writes = Future<void>.value();
  PhotoAngle? _recoveryAngle;

  @override
  PhotoFlowState build() {
    _picker = ref.watch(imagePickerProvider);
    _drafts = ref.watch(draftPhotoStoreProvider);
    _recoveryAngle = ref.read(initialPickingAngleProvider);
    final Map<PhotoAngle, XFile> initial = ref.read(initialDraftProvider);
    return PhotoFlowState(
      front: initial[PhotoAngle.front],
      side: initial[PhotoAngle.side],
      back: initial[PhotoAngle.back],
    );
  }

  bool get isComplete => state.isComplete;

  Future<void> select(PhotoAngle angle, {required ImageSource source}) async {
    if (state.isPicking) {
      return;
    }

    final PhotoFlowState beforePick = state;
    final int operation = ++_operationGeneration;
    state = state.copyWith(
      pendingAngle: angle,
      errorAngle: null,
      errorMessage: null,
    );
    // Remember the angle in case Android ends the app while the picker is open.
    unawaited(_persist());

    final XFile? photo;
    try {
      photo = await _picker.pickImage(source: source);
    } on Object {
      if (operation != _operationGeneration) {
        return;
      }
      state = beforePick.copyWith(
        pendingAngle: null,
        errorAngle: angle,
        errorMessage: '照片选择失败，请重试',
      );
      unawaited(_persist());
      return;
    }
    if (operation != _operationGeneration) {
      return;
    }
    if (photo == null) {
      state = beforePick.copyWith(pendingAngle: null);
      unawaited(_persist());
      return;
    }
    await _adoptInto(beforePick, angle, photo, operation);
  }

  Future<void> replace(PhotoAngle angle, {required ImageSource source}) {
    return select(angle, source: source);
  }

  /// Validates and stores [photo] for [angle]; a rejected file keeps the previous photo.
  Future<void> _adoptInto(
    PhotoFlowState base,
    PhotoAngle angle,
    XFile photo,
    int operation,
  ) async {
    final XFile adopted;
    try {
      adopted = await _drafts.adopt(angle, photo);
    } on PhotoRejected catch (rejected) {
      if (operation == _operationGeneration) {
        state = base.copyWith(
          pendingAngle: null,
          errorAngle: angle,
          errorMessage: rejected.message,
        );
        unawaited(_persist());
      }
      return;
    } on Object {
      if (operation == _operationGeneration) {
        state = base.copyWith(
          pendingAngle: null,
          errorAngle: angle,
          errorMessage: '照片无法保存，请重试。',
        );
        unawaited(_persist());
      }
      return;
    }
    if (operation != _operationGeneration) {
      unawaited(_drafts.release(adopted));
      return;
    }
    final XFile? previous = base.photoFor(angle);
    state = _withPhoto(
      base,
      angle,
      adopted,
    ).copyWith(pendingAngle: null, errorAngle: null, errorMessage: null);
    if (previous != null && previous.path != adopted.path) {
      unawaited(_drafts.release(previous));
    }
    unawaited(_persist());
  }

  void remove(PhotoAngle angle) {
    _operationGeneration++;
    final XFile? previous = state.photoFor(angle);
    state = _withPhoto(state, angle, null).copyWith(
      pendingAngle: null,
      errorAngle: state.errorAngle == angle ? null : state.errorAngle,
      errorMessage: state.errorAngle == angle ? null : state.errorMessage,
    );
    if (previous != null) {
      unawaited(_drafts.release(previous));
    }
    unawaited(_persist());
  }

  /// Removes a photo but keeps its file so 「撤销」 can put it back; see [dropDetached].
  XFile? detach(PhotoAngle angle) {
    _operationGeneration++;
    final XFile? previous = state.photoFor(angle);
    state = _withPhoto(state, angle, null).copyWith(
      pendingAngle: null,
      errorAngle: state.errorAngle == angle ? null : state.errorAngle,
      errorMessage: state.errorAngle == angle ? null : state.errorMessage,
    );
    unawaited(_persist());
    return previous;
  }

  /// Puts a detached photo back (撤销) if its slot is still empty and its file still exists.
  bool restorePhoto(PhotoAngle angle, XFile photo) {
    if (state.photoFor(angle) != null || state.isPicking) {
      unawaited(dropDetached(photo));
      return false;
    }
    if (!_drafts.isAvailable(photo)) {
      return false;
    }
    _operationGeneration++;
    state = _withPhoto(state, angle, photo);
    unawaited(_persist());
    return true;
  }

  /// Deletes a detached photo's file once undo is no longer offered.
  Future<void> dropDetached(XFile photo) async {
    for (final PhotoAngle angle in PhotoAngle.values) {
      if (state.photoFor(angle)?.path == photo.path) {
        return;
      }
    }
    await _drafts.release(photo);
  }

  void clearError() {
    state = state.copyWith(errorAngle: null, errorMessage: null);
  }

  /// Discards the draft and its files (「放弃草稿」, clear-all).
  Future<void> reset() {
    _operationGeneration++;
    final List<XFile> previous = <XFile>[
      for (final PhotoAngle angle in PhotoAngle.values)
        if (state.photoFor(angle) != null) state.photoFor(angle)!,
    ];
    state = const PhotoFlowState();
    return Future.wait(<Future<void>>[
      for (final XFile photo in previous) _drafts.release(photo),
      _persist(),
    ]);
  }

  /// Hands the complete draft to a submitted record, which then owns read-only copies.
  ///
  /// The photos are copied into [targetDir] and passed to [commit] (which stores the record);
  /// only after [commit] succeeds is the draft cleared. If copying or [commit] fails the
  /// draft is unchanged and the error is rethrown. Returns the paths in front/side/back order.
  Future<List<String>> handOff(
    Directory targetDir, {
    required Future<void> Function(List<String> paths) commit,
  }) async {
    if (!state.isComplete || state.isPicking) {
      throw StateError('The draft is not ready to submit');
    }
    final int operation = ++_operationGeneration;
    final PhotoFlowState submitted = state;
    final List<String> paths = await _drafts.copyTo(submitted, targetDir);
    await commit(paths);
    if (operation == _operationGeneration) {
      state = const PhotoFlowState();
    }
    for (final PhotoAngle angle in PhotoAngle.values) {
      final XFile photo = submitted.photoFor(angle)!;
      // The record has its own copies; the draft's files are no longer needed.
      if (state.photoFor(angle)?.path != photo.path) {
        unawaited(_drafts.release(photo));
      }
    }
    await _persist();
    return paths;
  }

  /// Replaces the draft with copies of a record's photos (保存为草稿 / 用这组照片重新生成).
  /// A non-empty draft is replaced only with [replaceExisting] (after the user agreed).
  Future<DraftRestore> restoreDraft(
    Map<PhotoAngle, String> sources, {
    Set<PhotoAngle> leaveEmpty = const <PhotoAngle>{},
    bool replaceExisting = false,
  }) async {
    if (state.isPicking || (!state.isEmpty && !replaceExisting)) {
      return DraftRestore.draftNotEmpty;
    }
    final int operation = ++_operationGeneration;
    final PhotoFlowState previous = state;
    final Map<PhotoAngle, XFile> restored = <PhotoAngle, XFile>{};
    try {
      for (final MapEntry<PhotoAngle, String> entry in sources.entries) {
        if (!leaveEmpty.contains(entry.key)) {
          if (!_drafts.isAvailable(XFile(entry.value))) {
            throw const PhotoRejected('missing');
          }
          restored[entry.key] = await _drafts.restore(entry.key, entry.value);
        }
      }
    } on Object catch (error) {
      for (final XFile photo in restored.values) {
        unawaited(_drafts.release(photo));
      }
      return error is PhotoRejected
          ? DraftRestore.unavailable
          : DraftRestore.failed;
    }
    if (operation != _operationGeneration) {
      for (final XFile photo in restored.values) {
        unawaited(_drafts.release(photo));
      }
      return DraftRestore.failed;
    }
    state = PhotoFlowState(
      front: restored[PhotoAngle.front],
      side: restored[PhotoAngle.side],
      back: restored[PhotoAngle.back],
    );
    for (final PhotoAngle angle in PhotoAngle.values) {
      final XFile? old = previous.photoFor(angle);
      if (old != null) {
        unawaited(_drafts.release(old));
      }
    }
    await _persist();
    return DraftRestore.restored;
  }

  /// Serialised draft writes, so a reset or clear never races an in-flight save.
  Future<void> _persist() {
    final PhotoFlowState snapshot = state;
    _writes = _writes.then((_) async {
      try {
        await _drafts.persist(snapshot);
      } on Object catch (error) {
        debugPrint('Draft could not be saved: $error');
      }
    });
    return _writes;
  }

  Future<void> retrieveLostData() async {
    final Future<void>? activeRecovery = _lostDataRecovery;
    if (activeRecovery != null) {
      await activeRecovery;
      return;
    }

    final Future<void> recovery = _retrieveLostDataOnce();
    _lostDataRecovery = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_lostDataRecovery, recovery)) {
        _lostDataRecovery = null;
      }
    }
  }

  Future<void> _retrieveLostDataOnce() async {
    if (!ref.read(lostDataRecoverySupportedProvider)) {
      return;
    }

    final int operationAtStart = _operationGeneration;
    final PhotoFlowState stateAtStart = state;
    final PhotoAngle? recoveryAngle = _recoveryAngle;
    _recoveryAngle = null;
    final PhotoAngle? target =
        stateAtStart.pendingAngle ??
        recoveryAngle ??
        _firstEmptyAngle(stateAtStart);

    final LostDataResponse response;
    try {
      response = await _picker.retrieveLostData();
    } on Object {
      return;
    }

    if (response.isEmpty) {
      if (recoveryAngle != null) {
        unawaited(_persist());
      }
      return;
    }

    if (operationAtStart != _operationGeneration ||
        !identical(state, stateAtStart) ||
        target == null) {
      return;
    }

    final XFile? recovered = response.file ?? response.files?.firstOrNull;
    if (recovered != null && response.type != RetrieveType.video) {
      final int operation = ++_operationGeneration;
      await _adoptInto(stateAtStart, target, recovered, operation);
      return;
    }

    if (response.exception != null) {
      _operationGeneration++;
      state = stateAtStart.copyWith(
        pendingAngle: null,
        errorAngle: target,
        errorMessage: '照片恢复失败，请重新选择',
      );
    }
  }

  PhotoAngle? _firstEmptyAngle(PhotoFlowState current) {
    for (final PhotoAngle angle in PhotoAngle.values) {
      if (current.photoFor(angle) == null) {
        return angle;
      }
    }
    return null;
  }

  PhotoFlowState _withPhoto(
    PhotoFlowState current,
    PhotoAngle angle,
    XFile? photo,
  ) {
    return switch (angle) {
      PhotoAngle.front => current.copyWith(front: photo),
      PhotoAngle.side => current.copyWith(side: photo),
      PhotoAngle.back => current.copyWith(back: photo),
    };
  }
}
