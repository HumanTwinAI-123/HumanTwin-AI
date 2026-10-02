import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/storage/local_store.dart';
import '../../shared/ui/ht_ui.dart';
import '../generation/digital_twin_repository.dart';
import 'generation_record.dart';
import 'library_controller.dart';

/// Render of the bundled sample model (assets/models/human_demo.glb) used as its thumbnail.
const String sampleThumbnailAsset = 'assets/images/thumb_sample.png';

/// 「今天 10:24」 / 「昨天 18:12」 / 「9月21日 09:30」.
String formatRecordTime(DateTime time, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final String hm = '${two(time.hour)}:${two(time.minute)}';
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(time.year, time.month, time.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) {
    return '今天 $hm';
  }
  if (diff == 1) {
    return '昨天 $hm';
  }
  return '${time.month}月${time.day}日 $hm';
}

String formatBytes(int? bytes) {
  if (bytes == null) {
    return '—';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// Space the avatars' own model files take on this phone. Simulated results point at the
/// sample bundled with the app, which takes no extra space however many there are.
int storedModelBytes(Iterable<GenerationRecord> avatars) => avatars.fold<int>(
  0,
  (int sum, GenerationRecord r) =>
      sum + (r.model != null && !r.model!.isAsset ? (r.modelBytes ?? 0) : 0),
);

/// 「N 个形象」 plus the extra space they use, when there is any.
String avatarStorageSummary(Iterable<GenerationRecord> avatars) {
  final int bytes = storedModelBytes(avatars);
  final String count = '${avatars.length} 个形象';
  return bytes == 0 ? count : '$count · ${formatBytes(bytes)}';
}

ChipTone recordTone(GenerationRecord record) {
  return switch (record.status) {
    RecordStatus.queued => ChipTone.queued,
    RecordStatus.done => ChipTone.success,
    RecordStatus.failed ||
    RecordStatus.rejected ||
    RecordStatus.lost => ChipTone.danger,
    _ =>
      record.info.group == StatusGroup.active
          ? ChipTone.processing
          : ChipTone.warning,
  };
}

String recordStatusLabel(GenerationRecord record) {
  if (record.status == RecordStatus.submitting &&
      record.mode == GenerationMode.mock) {
    return '准备中';
  }
  if (record.status == RecordStatus.processing && record.progress != null) {
    return '生成中 ${record.progress}%';
  }
  return record.info.label;
}

class RecordStatusChip extends StatelessWidget {
  const RecordStatusChip({
    required this.record,
    this.onMedia = false,
    this.large = false,
    super.key,
  });

  final GenerationRecord record;
  final bool onMedia;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final ChipTone tone = recordTone(record);
    final StatusGroup group = record.info.group;
    return HtChip(
      label: recordStatusLabel(record),
      tone: tone,
      dot: group == StatusGroup.active,
      icon: group == StatusGroup.done
          ? Icons.check_rounded
          : group == StatusGroup.attention
          ? (tone == ChipTone.danger
                ? Icons.error_outline_rounded
                : Icons.warning_amber_rounded)
          : null,
      onMedia: onMedia,
      large: large,
    );
  }
}

/// 示例模型 / 模拟 · 示例模型 / AI 生成 — shown wherever a result appears.
class OriginBadge extends StatelessWidget {
  const OriginBadge({
    required this.simulated,
    this.short = false,
    this.onMedia = false,
    this.sample = false,
    super.key,
  });

  final bool simulated;
  final bool short;
  final bool onMedia;

  /// The built-in sample (not produced by a generation run).
  final bool sample;

  @override
  Widget build(BuildContext context) {
    if (!simulated) {
      return HtChip(
        label: 'AI 生成',
        tone: ChipTone.ai,
        icon: Icons.auto_awesome_rounded,
        onMedia: onMedia,
        semanticLabel: 'AI 生成的模型',
      );
    }
    return HtChip(
      label: sample || short ? '示例模型' : '模拟 · 示例模型',
      tone: ChipTone.sample,
      icon: Icons.view_in_ar_rounded,
      onMedia: onMedia,
      semanticLabel: sample ? '内置示例模型，非本人' : '模拟生成，结果为示例模型，并非根据照片重建',
    );
  }
}

/// 4:5 thumbnail of a finished record (sample render, or a stored thumbnail).
class AvatarThumbnail extends ConsumerWidget {
  const AvatarThumbnail({
    required this.record,
    this.top = const <Widget>[],
    this.showOrigin = true,
    this.radius = AppRadii.medium,
    super.key,
  });

  final GenerationRecord record;
  final List<Widget> top;
  final bool showOrigin;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget image;
    if (record.isSimulated &&
        record.model?.isAsset == true &&
        record.model?.value == sampleModelAsset) {
      image = Image.asset(sampleThumbnailAsset, fit: BoxFit.cover);
    } else {
      final File thumb = ref
          .read(localStoreProvider)
          .file('records/${record.id}/thumb.png');
      image = thumb.existsSync()
          ? Image.file(thumb, fit: BoxFit.cover)
          : const _MarkPlaceholder();
    }
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: viewerGradient),
          position: DecorationPosition.background,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ExcludeSemantics(child: image),
              if (top.isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  right: 8,
                  child: Wrap(spacing: 6, runSpacing: 6, children: top),
                ),
              if (showOrigin)
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: OriginBadge(
                      simulated: record.isSimulated,
                      short: true,
                      onMedia: true,
                    ),
                  ),
                ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const RadialGradient viewerGradient = RadialGradient(
  center: Alignment(0, -0.2),
  radius: 1.1,
  colors: <Color>[Color(0xFF1D2939), Color(0xFF121821), Color(0xFF0F141B)],
  stops: <double>[0, 0.6, 1],
);

class _MarkPlaceholder extends StatelessWidget {
  const _MarkPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.35,
        child: Image.asset('assets/images/brand/humantwin_mark.png', width: 64),
      ),
    );
  }
}

/// Thumbnail for an unfinished record: its front photo dimmed, with progress or a status icon.
class TaskThumbnail extends ConsumerWidget {
  const TaskThumbnail({
    required this.record,
    this.small = false,
    this.showChip = true,
    super.key,
  });

  final GenerationRecord record;
  final bool small;
  final bool showChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LocalStore store = ref.read(localStoreProvider);
    File? front;
    if (record.inputs.isNotEmpty) {
      final String path = record.inputs.first;
      front = path.startsWith('/') ? File(path) : store.file(path);
    }
    final StatusGroup group = record.info.group;
    final bool danger = recordTone(record) == ChipTone.danger;
    final Widget overlay = group == StatusGroup.active
        ? ProgressRing(
            progress: record.status == RecordStatus.processing
                ? record.progress
                : null,
            size: small ? 34 : 52,
            stroke: small ? 4 : 5,
            showLabel: !small,
          )
        : Container(
            width: small ? 30 : 48,
            height: small ? 30 : 48,
            decoration: BoxDecoration(
              color: AppColors.tint(
                danger ? AppColors.error : AppColors.warning,
              ),
              borderRadius: BorderRadius.circular(small ? 10 : 16),
            ),
            child: Icon(
              danger
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              size: small ? 18 : 26,
              color: danger ? AppColors.error : AppColors.warning,
            ),
          );
    final double radius = small ? AppRadii.small : AppRadii.medium;
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const DecoratedBox(
              decoration: BoxDecoration(gradient: viewerGradient),
            ),
            if (front != null && front.existsSync())
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0.35,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF6B7280),
                      BlendMode.saturation,
                    ),
                    child: Image.file(front, fit: BoxFit.cover),
                  ),
                ),
              ),
            Center(child: overlay),
            if (showChip)
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RecordStatusChip(record: record, onMedia: true),
                ),
              ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-line description of where a record stands (Home cards).
String recordLine(GenerationRecord record) {
  final bool mock = record.mode == GenerationMode.mock;
  return switch (record.status) {
    RecordStatus.submitting => mock ? '正在准备模拟任务' : '正在上传照片并创建任务',
    RecordStatus.queued => '已提交，等待服务开始处理',
    RecordStatus.processing =>
      '${mock ? '模拟生成中' : '生成中'}${record.progress == null ? '' : ' · ${record.progress}%'}',
    RecordStatus.saving => mock ? '正在保存到「我的形象」' : '正在下载模型到本机',
    RecordStatus.checking => '正在向服务核对提交结果',
    RecordStatus.done => '已保存到「我的形象」',
    RecordStatus.failed => '生成未成功 · 照片仍保留',
    RecordStatus.rejected => '照片未通过检查 · 未创建任务',
    RecordStatus.timeout => '生成时间较长，已暂停查询',
    RecordStatus.paused => '已停止查询，任务仍在服务端进行',
    RecordStatus.credits => '生成额度不足 · 未创建任务',
    RecordStatus.offline => '无法连接，照片未发出',
    RecordStatus.config => '生成服务暂不可用 · 未创建任务',
    RecordStatus.connection => '暂时无法获取进度',
    RecordStatus.unknown => '无法确认是否提交成功，请先确认',
    RecordStatus.unresolved => '需要人工确认，暂不会重新提交',
    RecordStatus.downloadFailed => '模型已生成，下载未完成',
    RecordStatus.lost => '找不到这次生成的记录',
  };
}

/// Home / library card for an unfinished record; opens its progress page.
class TaskCard extends ConsumerWidget {
  const TaskCard({required this.record, required this.onTap, super.key});

  final GenerationRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ChipTone tone = recordTone(record);
    final Color lineColor = record.info.group == StatusGroup.attention
        ? (tone == ChipTone.danger ? AppColors.error : AppColors.warning)
        : AppColors.textSecondary;
    return HtCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      semanticLabel: '${record.name}，${recordStatusLabel(record)}',
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            child: TaskThumbnail(record: record, small: true, showChip: false),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.name,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: isLargeText(context) ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    recordLine(record),
                    style: text.bodyMedium?.copyWith(color: lineColor),
                  ),
                  if (record.info.group == StatusGroup.active) ...<Widget>[
                    const SizedBox(height: 6),
                    BrandProgressBar(
                      value: record.status == RecordStatus.processing
                          ? record.progress
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// Watches only the record with [id] (rebuilds on its changes).
GenerationRecord? watchRecord(WidgetRef ref, String id) =>
    ref.watch(libraryControllerProvider.select((LibraryState s) => s.byId(id)));
