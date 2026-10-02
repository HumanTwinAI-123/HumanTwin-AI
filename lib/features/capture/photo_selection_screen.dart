import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import 'photo_flow_controller.dart';
import 'photo_guide_screen.dart';

/// 选择照片 (step 2/3). PhotoFlowController owns the photos; the draft persists on its own.
class PhotoSelectionScreen extends ConsumerWidget {
  const PhotoSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PhotoFlowState photos = ref.watch(photoFlowControllerProvider);
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> missing = <String>[
      for (final PhotoAngle angle in PhotoAngle.values)
        if (photos.photoFor(angle) == null) angleLabels[angle]!,
    ];
    final PhotoAngle? errorAngle = photos.errorAngle;
    return PopScope<Object?>(
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop && !ref.read(photoFlowControllerProvider).isEmpty) {
          showHtSnack(context, '已保存为草稿，可在首页继续');
        }
      },
      child: Scaffold(
        appBar: const HtAppBar(title: '选择照片', step: (2, 3)),
        body: PageBody(
          children: <Widget>[
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text('添加三张全身照', style: text.headlineMedium),
            ),
            const SizedBox(height: 4),
            Text('点按每个位置拍摄或从相册选择。', style: text.bodyMedium),
            Align(
              alignment: Alignment.centerLeft,
              child: LinkButton(
                label: '查看拍摄说明',
                icon: Icons.description_outlined,
                onPressed: () => context.push('/create/guide?mode=back'),
              ),
            ),
            const SizedBox(height: 4),
            PhotoSlots(photos: photos),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: photos.isComplete
                  ? Row(
                      children: <Widget>[
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '三张照片已就绪',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '已添加 ${photos.count}/3 · 还差：${missing.join('、')}',
                      style: text.bodyMedium,
                    ),
            ),
            if (errorAngle != null && photos.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              HtBanner(
                tone: BannerTone.danger,
                title: photos.photoFor(errorAngle) == null
                    ? '${angleLabels[errorAngle]}照片无法使用'
                    : '新的${angleLabels[errorAngle]}照片无法使用，原来的照片已保留',
                body: photos.errorMessage,
                actions: <Widget>[
                  LinkButton(
                    label: '重新选择',
                    onPressed: () =>
                        showPhotoSourceSheet(context, ref, errorAngle),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            HtBanner(
              tone: BannerTone.neutral,
              icon: Icons.lock_outline_rounded,
              body: demo ? '照片只保存在这台手机上。演示版不会上传照片。' : '照片只保存在这台手机上，提交生成前不会上传。',
            ),
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          children: <Widget>[
            Semantics(
              hint: photos.isComplete ? null : '还差 ${missing.length} 张照片',
              child: PrimaryButton(
                label: '下一步',
                onPressed: photos.isComplete && !photos.isPicking
                    ? () => context.push('/create/review')
                    : null,
              ),
            ),
            if (!photos.isComplete)
              ActionHint('还差 ${missing.length} 张：${missing.join('、')}'),
          ],
        ),
      ),
    );
  }
}

/// The three photo slots (grid; list at large text). Shared with the review page.
class PhotoSlots extends ConsumerWidget {
  const PhotoSlots({required this.photos, this.allowDelete = true, super.key});

  final PhotoFlowState photos;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool list = isLargeText(context);
    final List<Widget> tiles = <Widget>[
      for (final PhotoAngle angle in PhotoAngle.values)
        _PhotoTile(
          angle: angle,
          photos: photos,
          list: list,
          onTap: () => showPhotoSourceSheet(
            context,
            ref,
            angle,
            allowDelete: allowDelete,
          ),
        ),
    ];
    if (list) {
      return Column(
        children: <Widget>[
          for (final Widget tile in tiles)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < tiles.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.angle,
    required this.photos,
    required this.list,
    required this.onTap,
  });

  final PhotoAngle angle;
  final PhotoFlowState photos;
  final bool list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final XFile? photo = photos.photoFor(angle);
    final bool error = photos.errorAngle == angle && photo == null;
    final bool loading = photos.pendingAngle == angle;
    final String label = angleLabels[angle]!;
    final String state = error
        ? '无法使用'
        : photo != null
        ? '已添加'
        : '待添加';

    final Widget frame = AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: error
                ? AppColors.error
                : photo != null
                ? AppColors.borderSubtle
                : AppColors.borderStrong,
            width: error ? 2 : 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.medium - 1),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (photo != null)
                Image.file(
                  File(photo.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(),
                )
              else if (error)
                const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 30,
                    color: AppColors.error,
                  ),
                )
              else ...<Widget>[
                Opacity(
                  opacity: 0.2,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF808080),
                      BlendMode.saturation,
                    ),
                    child: Image.asset(
                      guideImages[angle]!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.tonalBackground,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.tonalForeground,
                    ),
                  ),
                ),
              ],
              if (photo != null || error)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: error ? AppColors.error : AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      error ? Icons.close_rounded : Icons.check_rounded,
                      size: 14,
                      color: error
                          ? const Color(0xFF1B0808)
                          : const Color(0xFF07140E),
                    ),
                  ),
                ),
              if ((photo != null || error) && !list)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[Color(0xE6080B0F), Color(0x00080B0F)],
                      ),
                    ),
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Text(
                        error ? '需更换' : '更换',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              if (loading)
                ColoredBox(
                  color: const Color(0xB80D1117),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 6),
                      Text('正在读取', style: text.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final Widget caption = list
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: text.titleMedium),
              Text(
                state,
                style: text.bodyMedium?.copyWith(
                  color: error ? AppColors.error : AppColors.textSecondary,
                ),
              ),
              Text(
                photo != null || error ? '点按更换' : '点按添加',
                style: text.bodySmall,
              ),
            ],
          )
        : Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: <Widget>[
              Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                state,
                style: text.bodySmall?.copyWith(
                  color: error ? AppColors.error : AppColors.textTertiary,
                ),
              ),
            ],
          );
    return Semantics(
      button: true,
      label: '$label照片，$state，${photo != null || error ? '双击更换或删除' : '双击添加'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: loading ? null : onTap,
        child: list
            ? Row(
                children: <Widget>[
                  SizedBox(width: 88, child: frame),
                  const SizedBox(width: 16),
                  Expanded(child: caption),
                ],
              )
            : Column(
                children: <Widget>[frame, const SizedBox(height: 8), caption],
              ),
      ),
    );
  }
}

/// 添加/更换照片: system camera (no permission is declared, so none is requested) or the system
/// photo picker; delete offers 撤销.
Future<void> showPhotoSourceSheet(
  BuildContext context,
  WidgetRef ref,
  PhotoAngle angle, {
  bool allowDelete = true,
}) {
  final PhotoFlowState photos = ref.read(photoFlowControllerProvider);
  final bool has = photos.photoFor(angle) != null || photos.errorAngle == angle;
  final String label = angleLabels[angle]!;
  final String subtitle = switch (angle) {
    PhotoAngle.front => '面向镜头，自然站立',
    PhotoAngle.side => '侧身站立，面向左侧或右侧均可',
    PhotoAngle.back => '背对镜头，自然站立',
  };
  final PhotoFlowController controller = ref.read(
    photoFlowControllerProvider.notifier,
  );
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  return showHtSheet<void>(context, (BuildContext sheetContext) {
    void pick(ImageSource source) {
      Navigator.of(sheetContext).pop();
      controller.select(angle, source: source);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(
          title: '${has || !allowDelete ? '更换' : '添加'}$label照片',
          subtitle: subtitle,
        ),
        Material(
          type: MaterialType.transparency,
          child: Column(
            children: <Widget>[
              HtListItem(
                icon: Icons.photo_camera_outlined,
                tinted: true,
                title: '拍摄照片',
                subtitle: '打开系统相机，建议请他人帮忙拍摄',
                chevron: false,
                onTap: () => pick(ImageSource.camera),
              ),
              HtListItem(
                icon: Icons.photo_library_outlined,
                tinted: true,
                title: '从相册选择',
                subtitle: '打开系统照片选择器',
                chevron: false,
                onTap: () => pick(ImageSource.gallery),
              ),
              if (has && allowDelete)
                HtListItem(
                  icon: Icons.delete_outline_rounded,
                  title: '删除这张照片',
                  danger: true,
                  chevron: false,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final XFile? removed = controller.detach(angle);
                    if (removed == null) {
                      return;
                    }
                    bool undone = false;
                    messenger.hideCurrentSnackBar();
                    messenger
                        .showSnackBar(
                          SnackBar(
                            content: Text('已删除$label照片'),
                            action: SnackBarAction(
                              label: '撤销',
                              onPressed: () {
                                undone = true;
                                controller.restorePhoto(angle, removed);
                              },
                            ),
                          ),
                        )
                        .closed
                        .then((_) {
                          if (!undone) {
                            controller.dropDetached(removed);
                          }
                        });
                  },
                ),
            ],
          ),
        ),
        SheetBody(
          child: SecondaryButton(
            label: '取消',
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ],
    );
  });
}
