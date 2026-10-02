import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../capture/photo_flow_controller.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import '../library/record_widgets.dart';
import '../onboarding/welcome_screen.dart';
import '../settings/app_settings.dart';

/// Starts or continues creation: an existing draft goes straight to the photos.
void startCreation(BuildContext context, WidgetRef ref) {
  final bool hasDraft = !ref.read(photoFlowControllerProvider).isEmpty;
  if (hasDraft || !ref.read(appSettingsProvider).showGuide) {
    context.push('/create/photos');
  } else {
    context.push('/create/guide');
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState library = ref.watch(libraryControllerProvider);
    final PhotoFlowState draft = ref.watch(photoFlowControllerProvider);
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final bool fresh = library.records.isEmpty && draft.isEmpty;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.gutter(context),
        title: const BrandLockup(),
        actions: <Widget>[
          if (demo) const DemoChipButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: fresh
          ? _FirstHome(demo: demo)
          : _ReturningHome(library: library, draft: draft, demo: demo),
    );
  }
}

class _FirstHome extends ConsumerWidget {
  const _FirstHome({required this.demo});

  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final double heroHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(
      200,
      280,
    );
    return PageBody(
      children: <Widget>[
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text.rich(
            const TextSpan(
              text: '创建你的\n',
              children: <InlineSpan>[
                TextSpan(
                  text: '3D 形象',
                  style: TextStyle(color: AppColors.brandCyan),
                ),
              ],
            ),
            style: text.displaySmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          demo
              ? '准备 3 张全身照片，体验从拍摄到 3D 查看的完整流程。'
              : '准备 3 张全身照片，生成一个可以旋转查看的 3D 形象。',
          style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        HeroIllustration(height: heroHeight, demo: demo),
        const SizedBox(height: 20),
        PrimaryButton(
          label: '开始创建',
          icon: Icons.add_rounded,
          hero: true,
          onPressed: () => startCreation(context, ref),
        ),
        const SizedBox(height: 8),
        TonalButton(
          label: '先看看示例形象',
          icon: Icons.view_in_ar_rounded,
          onPressed: () => context.push('/sample'),
        ),
        const SectionHeader(title: '三步完成'),
        HtListGroup(
          children: <Widget>[
            const HtListItem(
              icon: Icons.photo_camera_outlined,
              title: '拍摄或选择 3 张全身照',
              subtitle: '正面、侧面、背面',
            ),
            HtListItem(
              icon: Icons.hourglass_empty_rounded,
              title: demo ? '等待模拟生成' : '等待生成',
              subtitle: demo ? '约 5 秒，不会上传照片' : '耗时取决于生成服务，可离开页面',
            ),
            const HtListItem(
              icon: Icons.view_in_ar_rounded,
              title: '查看、保存与分享',
              subtitle: '形象保存在这台手机上',
            ),
          ],
        ),
        if (demo) ...<Widget>[
          const SizedBox(height: 16),
          const DemoQualifierBanner(),
        ],
        const SizedBox(height: 16),
        _PrivacyRow(demo: demo),
      ],
    );
  }
}

class _ReturningHome extends ConsumerWidget {
  const _ReturningHome({
    required this.library,
    required this.draft,
    required this.demo,
  });

  final LibraryState library;
  final PhotoFlowState draft;
  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<GenerationRecord> attention = library.attention;
    final List<GenerationRecord> active = library.active;
    final List<GenerationRecord> finished = library.justFinished;
    final List<GenerationRecord> avatars = library.avatars;
    final DateTime now = ref.read(clockProvider)();
    return PageBody(
      children: <Widget>[
        const SizedBox(height: 8),
        draft.isEmpty ? const _CreateCard() : _DraftCard(draft: draft),
        if (attention.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: '需要你处理',
            trailing: HtChip(
              label: '${attention.length}',
              tone: ChipTone.warning,
            ),
          ),
          for (final GenerationRecord record in attention)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TaskCard(
                record: record,
                onTap: () => context.push('/tasks/${record.id}'),
              ),
            ),
        ],
        if (active.isNotEmpty) ...<Widget>[
          const SectionHeader(title: '进行中'),
          for (final GenerationRecord record in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TaskCard(
                record: record,
                onTap: () => context.push('/tasks/${record.id}'),
              ),
            ),
        ],
        if (finished.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          HtBanner(
            tone: BannerTone.success,
            title: '形象已保存',
            body: '「${finished.first.name}」已保存到我的形象。',
            actions: <Widget>[
              LinkButton(
                label: '查看',
                onPressed: () => context.push('/avatars/${finished.first.id}'),
              ),
            ],
          ),
        ],
        SectionHeader(
          title: '我的形象',
          trailing: avatars.isEmpty
              ? null
              : TextButton(
                  onPressed: () => context.go('/library'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('全部 ${avatars.length}'),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
        ),
        if (avatars.isEmpty)
          HtCard(
            child: Text(
              '完成的形象会显示在这里。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          SizedBox(
            height: _RecentAvatar.heightFor(context, avatars.take(6), now),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: avatars.length.clamp(0, 6),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int i) => _RecentAvatar(
                record: avatars[i],
                missing: library.missingFiles.contains(avatars[i].id),
                now: now,
              ),
            ),
          ),
        if (demo) ...<Widget>[
          const SizedBox(height: 20),
          const DemoQualifierBanner(),
        ],
        const SizedBox(height: 12),
        _PrivacyRow(demo: demo),
      ],
    );
  }
}

class _CreateCard extends ConsumerWidget {
  const _CreateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return HtCard(
      gradientBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text('创建新的 3D 形象', style: text.titleMedium),
                    ),
                    const SizedBox(height: 4),
                    Text('准备正面、侧面、背面 3 张全身照', style: text.bodyMedium),
                  ],
                ),
              ),
              if (!isLargeText(context)) ...<Widget>[
                const SizedBox(width: 16),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.tint(AppColors.accentPrimary, 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    size: 28,
                    color: AppColors.accentPrimary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: '开始创建',
            icon: Icons.add_rounded,
            onPressed: () => startCreation(context, ref),
          ),
        ],
      ),
    );
  }
}

class _DraftCard extends ConsumerWidget {
  const _DraftCard({required this.draft});

  final PhotoFlowState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return HtCard(
      gradientBorder: true,
      semanticLabel: '未完成的创建',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '草稿',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.brandCyan,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('继续创建形象', style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '已选 ${draft.count}/3 张照片${draft.errorAngle != null ? '，1 张需要更换' : ''}',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (!isLargeText(context))
                Row(
                  children: <Widget>[
                    for (final PhotoAngle angle in PhotoAngle.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _MiniPhoto(photo: draft.photoFor(angle)),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          ButtonPair(
            first: SecondaryButton(
              label: '放弃草稿',
              onPressed: () async {
                final bool discard = await showHtConfirm(
                  context,
                  title: '放弃这个草稿？',
                  paragraphs: const <String>[
                    '已选的照片会从 HumanTwin 中移除。从相册选择的原图不受影响；用相机拍摄的照片只保存在本应用中，放弃后无法找回。',
                  ],
                  confirmLabel: '放弃草稿',
                  destructive: true,
                );
                if (discard && context.mounted) {
                  await ref.read(photoFlowControllerProvider.notifier).reset();
                  if (context.mounted) {
                    showHtSnack(context, '已放弃草稿');
                  }
                }
              },
            ),
            second: PrimaryButton(
              label: '继续',
              onPressed: () => context.push('/create/photos'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPhoto extends StatelessWidget {
  const _MiniPhoto({required this.photo});

  final XFile? photo;

  @override
  Widget build(BuildContext context) {
    final XFile? photo = this.photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 45,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(
            color: photo == null
                ? AppColors.borderStrong
                : AppColors.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: photo == null
            ? const Icon(
                Icons.add_rounded,
                size: 16,
                color: AppColors.textTertiary,
              )
            : ExcludeSemantics(
                child: Image.file(File(photo.path), fit: BoxFit.cover),
              ),
      ),
    );
  }
}

class _RecentAvatar extends StatelessWidget {
  const _RecentAvatar({
    required this.record,
    required this.missing,
    required this.now,
  });

  final GenerationRecord record;
  final bool missing;
  final DateTime now;

  static double widthFor(BuildContext context) =>
      isLargeText(context) ? 176 : 128;

  /// The strip's height: a horizontal list cannot grow with its items, so lay out each
  /// item's name (at most two lines) and date at the current width and text size.
  static double heightFor(
    BuildContext context,
    Iterable<GenerationRecord> records,
    DateTime now,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    final double width = widthFor(context);
    double measure(String value, TextStyle? style, {int? maxLines}) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: width);
      final double height = painter.height;
      painter.dispose();
      return height;
    }

    double tallest = 0;
    for (final GenerationRecord record in records) {
      final double item =
          measure(record.name, text.labelMedium, maxLines: 2) +
          measure(formatRecordTime(record.createdAt, now), text.bodySmall);
      tallest = item > tallest ? item : tallest;
    }
    return width * 5 / 4 + 8 + tallest + 2;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: widthFor(context),
      child: Semantics(
        button: true,
        label:
            '${record.name}，${record.isSimulated ? '示例模型' : 'AI 生成'}${missing ? '，本机文件缺失' : ''}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          onTap: () => context.push('/avatars/${record.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AvatarThumbnail(
                record: record,
                top: <Widget>[
                  if (!record.resultSeen)
                    const HtChip(
                      label: '新',
                      tone: ChipTone.info,
                      onMedia: true,
                    ),
                  if (missing)
                    const HtChip(
                      label: '文件缺失',
                      tone: ChipTone.warning,
                      icon: Icons.image_not_supported_outlined,
                      onMedia: true,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                record.name,
                style: text.labelMedium?.copyWith(color: AppColors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                formatRecordTime(record.createdAt, now),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({required this.demo});

  final bool demo;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: HtListItem(
        icon: Icons.verified_user_outlined,
        title: demo ? '照片与形象仅保存在本机' : '形象保存在本机',
        subtitle: demo ? '演示版不会上传任何照片' : '只有提交生成时，三张照片才会发给第三方服务',
        onTap: () => context.push('/privacy'),
      ),
    );
  }
}
