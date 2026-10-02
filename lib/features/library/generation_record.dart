import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../generation/digital_twin_repository.dart';

/// Where generation runs. v1 ships [mock]; [service] is the developer-only local proxy path.
enum GenerationMode { mock, service }

/// Every user-facing state of a generation record (04-generation-assets-privacy-spec.md §2).
enum RecordStatus {
  submitting, // S1 (Mock: 准备中)
  queued, // S2
  processing, // S3
  saving, // S4
  done, // S5
  failed, // S6
  rejected, // S7  (nothing created)
  timeout, // S8
  credits, // S9  (nothing created)
  offline, // S10 (nothing created)
  config, // S10b (nothing created)
  connection, // S11
  unknown, // S12
  checking, // S12 → confirmSubmission in flight
  unresolved, // S13
  downloadFailed, // S14
  lost, // S16
  paused, // S17
}

enum StatusGroup { active, done, attention }

@immutable
class StatusInfo {
  const StatusInfo(this.label, this.group, {this.draftLike = false});

  final String label;
  final StatusGroup group;

  /// Nothing was created at the provider: never a library item, never lights the badge.
  final bool draftLike;
}

const Map<RecordStatus, StatusInfo> statusInfo = <RecordStatus, StatusInfo>{
  RecordStatus.submitting: StatusInfo('提交中', StatusGroup.active),
  RecordStatus.queued: StatusInfo('排队中', StatusGroup.active),
  RecordStatus.processing: StatusInfo('生成中', StatusGroup.active),
  RecordStatus.saving: StatusInfo('保存中', StatusGroup.active),
  RecordStatus.checking: StatusInfo('核对中', StatusGroup.active),
  RecordStatus.done: StatusInfo('已完成', StatusGroup.done),
  RecordStatus.failed: StatusInfo('未成功', StatusGroup.attention),
  RecordStatus.rejected: StatusInfo(
    '需换照片',
    StatusGroup.attention,
    draftLike: true,
  ),
  RecordStatus.timeout: StatusInfo('已暂停', StatusGroup.attention),
  RecordStatus.credits: StatusInfo(
    '额度不足',
    StatusGroup.attention,
    draftLike: true,
  ),
  RecordStatus.offline: StatusInfo(
    '未连接',
    StatusGroup.attention,
    draftLike: true,
  ),
  RecordStatus.config: StatusInfo(
    '服务异常',
    StatusGroup.attention,
    draftLike: true,
  ),
  RecordStatus.connection: StatusInfo('连接中断', StatusGroup.attention),
  RecordStatus.unknown: StatusInfo('待确认', StatusGroup.attention),
  RecordStatus.unresolved: StatusInfo('需人工确认', StatusGroup.attention),
  RecordStatus.downloadFailed: StatusInfo('下载失败', StatusGroup.attention),
  RecordStatus.lost: StatusInfo('记录丢失', StatusGroup.attention),
  RecordStatus.paused: StatusInfo('已暂停', StatusGroup.attention),
};

/// A provider task is (or may still be) running: a new submission must wait (one active generation).
const Set<RecordStatus> blockingStatuses = <RecordStatus>{
  RecordStatus.submitting,
  RecordStatus.queued,
  RecordStatus.processing,
  RecordStatus.saving,
  RecordStatus.checking,
  RecordStatus.timeout,
  RecordStatus.paused,
  RecordStatus.connection,
};

/// A submission may have been charged but is unconfirmed.
const Set<RecordStatus> unconfirmedStatuses = <RecordStatus>{
  RecordStatus.unknown,
  RecordStatus.unresolved,
};

/// The model a finished record shows: a bundled asset (sample) or a file in the record folder.
@immutable
class ModelRef {
  const ModelRef.asset(this.value) : isAsset = true;
  const ModelRef.file(this.value) : isAsset = false;

  final bool isAsset;

  /// Asset key, or a path relative to the store root.
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': isAsset ? 'asset' : 'file',
    'value': value,
  };

  static ModelRef? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final Object? value = json['value'];
    if (value is! String) {
      return null;
    }
    return json['kind'] == 'asset'
        ? ModelRef.asset(value)
        : ModelRef.file(value);
  }

  @override
  bool operator ==(Object other) =>
      other is ModelRef && other.isAsset == isAsset && other.value == value;

  @override
  int get hashCode => Object.hash(isAsset, value);
}

@immutable
class GenerationRecord {
  const GenerationRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.mode,
    required this.status,
    this.progress,
    this.taskId,
    this.origin,
    this.inputs = const <String>[],
    this.model,
    this.modelBytes,
    this.resultSeen = false,
    this.recovered = false,
    this.failureKind,
  });

  static const Object _keep = Object();

  final String id;
  final String name;
  final DateTime createdAt;
  final GenerationMode mode;
  final RecordStatus status;

  /// 0–100 while processing (kept in memory; not meaningful after restart).
  final int? progress;
  final String? taskId;
  final ModelOrigin? origin;

  /// Locked photo copies (front, side, back) relative to the store root, while needed.
  final List<String> inputs;
  final ModelRef? model;
  final int? modelBytes;

  /// The finished result has been opened (Home stops announcing it).
  final bool resultSeen;

  /// A 待确认 submission was checked and bound to a task.
  final bool recovered;
  final GenerationFailureKind? failureKind;

  StatusInfo get info => statusInfo[status]!;
  bool get isDone => status == RecordStatus.done;
  bool get isSimulated =>
      (origin ??
          (mode == GenerationMode.mock ? ModelOrigin.simulatedSample : null)) ==
      ModelOrigin.simulatedSample;
  bool get libraryVisible => !info.draftLike;

  GenerationRecord copyWith({
    String? name,
    RecordStatus? status,
    Object? progress = _keep,
    Object? taskId = _keep,
    Object? origin = _keep,
    List<String>? inputs,
    Object? model = _keep,
    Object? modelBytes = _keep,
    bool? resultSeen,
    bool? recovered,
    Object? failureKind = _keep,
  }) {
    return GenerationRecord(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      mode: mode,
      status: status ?? this.status,
      progress: identical(progress, _keep) ? this.progress : progress as int?,
      taskId: identical(taskId, _keep) ? this.taskId : taskId as String?,
      origin: identical(origin, _keep) ? this.origin : origin as ModelOrigin?,
      inputs: inputs ?? this.inputs,
      model: identical(model, _keep) ? this.model : model as ModelRef?,
      modelBytes: identical(modelBytes, _keep)
          ? this.modelBytes
          : modelBytes as int?,
      resultSeen: resultSeen ?? this.resultSeen,
      recovered: recovered ?? this.recovered,
      failureKind: identical(failureKind, _keep)
          ? this.failureKind
          : failureKind as GenerationFailureKind?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'mode': mode.name,
    'status': status.name,
    'taskId': taskId,
    'origin': origin?.name,
    'inputs': inputs,
    'model': model?.toJson(),
    'modelBytes': modelBytes,
    'resultSeen': resultSeen,
    'recovered': recovered,
    'failureKind': failureKind?.name,
  };

  static GenerationRecord? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final Object? id = json['id'];
    final Object? name = json['name'];
    final DateTime? createdAt = DateTime.tryParse('${json['createdAt']}');
    final RecordStatus? status = _byName(RecordStatus.values, json['status']);
    final GenerationMode? mode = _byName(GenerationMode.values, json['mode']);
    if (id is! String ||
        name is! String ||
        createdAt == null ||
        status == null ||
        mode == null) {
      return null;
    }
    final Object? inputs = json['inputs'];
    return GenerationRecord(
      id: id,
      name: name,
      createdAt: createdAt,
      mode: mode,
      status: status,
      taskId: json['taskId'] is String ? json['taskId']! as String : null,
      origin: _byName(ModelOrigin.values, json['origin']),
      inputs: inputs is List
          ? inputs.whereType<String>().toList()
          : const <String>[],
      model: ModelRef.fromJson(json['model']),
      modelBytes: json['modelBytes'] is int ? json['modelBytes']! as int : null,
      resultSeen: json['resultSeen'] == true,
      recovered: json['recovered'] == true,
      failureKind: _byName(GenerationFailureKind.values, json['failureKind']),
    );
  }
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final T value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}

/// Default record name: 示例形象 (demo results are the shared sample) or 我的形象 (service).
String suggestRecordName(
  Iterable<String> taken,
  GenerationMode mode,
  DateTime now,
) {
  final String base =
      '${mode == GenerationMode.mock ? '示例形象' : '我的形象'} ${now.month}月${now.day}日';
  final Set<String> names = taken.toSet();
  if (!names.contains(base)) {
    return base;
  }
  for (int i = 2; ; i++) {
    final String candidate = '$base ($i)';
    if (!names.contains(candidate)) {
      return candidate;
    }
  }
}

/// 1–20 characters (as the user sees them, like the text field's counter) after trimming.
String? validateRecordName(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.characters.length > 20) {
    return '请输入名称（1–20 个字）';
  }
  return null;
}

/// Export file name: reserved characters removed, ≤40 characters, origin suffix.
String exportBaseName(String name, {required bool simulated}) {
  String safe = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  if (safe.characters.length > 40) {
    safe = safe.characters.take(40).toString();
  }
  if (safe.isEmpty) {
    safe = 'HumanTwin_形象';
  }
  return '$safe${simulated ? '_示例' : '_AI生成'}';
}
