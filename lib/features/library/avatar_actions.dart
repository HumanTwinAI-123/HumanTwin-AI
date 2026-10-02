import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../share/share_controller.dart';
import 'generation_record.dart';
import 'library_controller.dart';
import 'record_widgets.dart';

/// 重命名: 1–20 characters, live validation, 保存 disabled while invalid.
Future<void> showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  GenerationRecord record,
) async {
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _RenameDialog(initial: record.name),
  );
  if (name == null || !context.mounted) {
    return;
  }
  if (name.trim() == record.name) {
    showHtSnack(context, '名称未更改');
    return;
  }
  await ref.read(libraryControllerProvider.notifier).rename(record.id, name);
  if (context.mounted) {
    showHtSnack(context, '已重命名');
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? error = validateRecordName(_controller.text);
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        key: const ValueKey<String>('rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: '形象名称',
          helperText: '保存在本机；分享或导出时用作文件名',
          errorText: error,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (String value) {
          if (validateRecordName(value) == null) {
            Navigator.of(context).pop(value.trim());
          }
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: error == null
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 删除形象 (deleteAvatar): names what is removed and what is not.
Future<bool> confirmDeleteAvatar(
  BuildContext context,
  WidgetRef ref,
  GenerationRecord record,
) async {
  final bool confirmed = await showHtConfirm(
    context,
    icon: Icons.delete_outline_rounded,
    title: '删除「${record.name}」？',
    paragraphs: <String>[
      '将从这台手机删除 3D 模型、缩略图和照片副本，无法恢复。',
      '已经分享或导出的文件不会被撤回。${record.isSimulated ? '' : '服务商处的照片和模型按其政策处理（模型最多约 3 天，照片保留期限待确认），本操作不会删除它们。'}',
    ],
    confirmLabel: '删除',
    destructive: true,
  );
  if (!confirmed) {
    return false;
  }
  final bool removed = await ref
      .read(libraryControllerProvider.notifier)
      .removeRecord(record.id);
  if (removed) {
    ref.read(shareControllerProvider.notifier).forget(record.id);
  }
  return removed;
}

/// 分享或导出: two v1 outputs, each opening an exact preview first.
Future<void> showShareOptions(
  BuildContext context,
  GenerationRecord record, {
  Future<void> Function()? beforeImage,
}) {
  return showHtSheet<void>(context, (BuildContext sheetContext) {
    final TextTheme text = Theme.of(sheetContext).textTheme;
    Widget option(IconData icon, String title, String body, String kind) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: HtCard(
          padding: const EdgeInsets.all(12),
          onTap: () async {
            Navigator.of(sheetContext).pop();
            if (kind == 'image') {
              // Capture the current view first (falls back to the stored render).
              await (beforeImage?.call() ??
                  ProviderScope.containerOf(context, listen: false)
                      .read(shareControllerProvider.notifier)
                      .captureSnapshot(record));
            }
            if (context.mounted) {
              unawaited(context.push('/avatars/${record.id}/share/$kind'));
            }
          },
          semanticLabel: '$title，$body',
          child: ExcludeSemantics(
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.tonalBackground,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.tonalForeground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(body, style: text.bodyMedium),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(title: '分享或导出', subtitle: '发送前会先预览内容'),
        SheetBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              option(Icons.image_outlined, '图片（PNG）', '形象快照，适合发给朋友', 'image'),
              option(
                Icons.view_in_ar_rounded,
                '3D 模型文件（GLB）',
                '可在 3D 查看器或建模软件中打开',
                'file',
              ),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('不会包含你的原始照片', style: text.bodyMedium)),
                ],
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: '取消',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  });
}

/// Long-press / ⋮ actions for a finished record in 我的形象.
Future<void> showAvatarMenu(
  BuildContext context,
  WidgetRef ref,
  GenerationRecord record,
) {
  return showHtSheet<void>(context, (BuildContext sheetContext) {
    final LibraryState library = ref.read(libraryControllerProvider);
    final bool missing = library.missingFiles.contains(record.id);
    final bool expired = library.expiredFiles.contains(record.id);
    final TextTheme text = Theme.of(sheetContext).textTheme;
    void close() => Navigator.of(sheetContext).pop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.gutter(sheetContext),
            0,
            AppSpacing.gutter(sheetContext),
            8,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 48,
                child: AvatarThumbnail(
                  record: record,
                  showOrigin: false,
                  radius: AppRadii.small,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(record.name, style: text.titleMedium),
                    Text(
                      '${formatRecordTime(record.createdAt, ref.read(clockProvider)())} · ${record.isSimulated ? '模拟生成 · 示例模型' : 'AI 生成'}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: Column(
            children: <Widget>[
              HtListItem(
                icon: Icons.view_in_ar_rounded,
                title: '查看',
                chevron: false,
                onTap: () {
                  close();
                  context.push('/avatars/${record.id}');
                },
              ),
              HtListItem(
                icon: Icons.edit_outlined,
                title: '重命名',
                chevron: false,
                onTap: () {
                  close();
                  showRenameDialog(context, ref, record);
                },
              ),
              if (!missing)
                HtListItem(
                  icon: Icons.share_outlined,
                  title: '分享或导出',
                  chevron: false,
                  onTap: () {
                    close();
                    showShareOptions(context, record);
                  },
                )
              else if (!expired)
                HtListItem(
                  icon: Icons.download_rounded,
                  title: '重新下载',
                  subtitle: '本机文件缺失；只下载同一任务的模型',
                  chevron: false,
                  onTap: () {
                    close();
                    context.push('/avatars/${record.id}?redownload=1');
                  },
                ),
              HtListItem(
                icon: Icons.delete_outline_rounded,
                title: '删除',
                danger: true,
                chevron: false,
                onTap: () async {
                  close();
                  final bool deleted = await confirmDeleteAvatar(
                    context,
                    ref,
                    record,
                  );
                  if (deleted && context.mounted) {
                    showHtSnack(context, '已删除「${record.name}」');
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  });
}
