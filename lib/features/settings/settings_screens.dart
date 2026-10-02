import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/storage/local_store.dart';
import '../../shared/ui/ht_ui.dart';
import '../capture/photo_flow_controller.dart';
import '../common/info_sheets.dart';
import '../generation/digital_twin_repository.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import '../library/record_widgets.dart';
import '../onboarding/welcome_screen.dart';
import '../share/share_controller.dart';
import 'app_settings.dart';

/// Shown in 设置/关于; keep in sync with `version` in pubspec.yaml.
const String appVersion = '0.1.0';

/// 设置: short, product-specific settings (no account, profile or analytics: v1 has none).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final GenerationMode mode = ref.watch(generationModeProvider);
    final LibraryState library = ref.watch(libraryControllerProvider);
    final bool demo = mode == GenerationMode.mock;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.gutter(context),
        title: Semantics(header: true, child: const Text('设置')),
      ),
      body: PageBody(
        children: <Widget>[
          const ListHeading('生成'),
          HtListGroup(
            children: <Widget>[
              HtListItem(
                icon: Icons.auto_awesome_outlined,
                title: '生成方式',
                subtitle: demo ? '模拟生成（演示版）' : '已配置的生成服务（开发用）',
                onTap: () => showModeInfoSheet(context, mode),
              ),
              MergeSemantics(
                child: HtListItem(
                  icon: Icons.description_outlined,
                  title: '创建前显示拍摄说明',
                  subtitle: '关闭后可在选择照片页查看',
                  chevron: false,
                  onTap: () => ref
                      .read(appSettingsProvider.notifier)
                      .setShowGuide(!settings.showGuide),
                  trailing: Switch(
                    value: settings.showGuide,
                    onChanged: (bool value) => ref
                        .read(appSettingsProvider.notifier)
                        .setShowGuide(value),
                  ),
                ),
              ),
            ],
          ),
          const ListHeading('隐私与数据'),
          HtListGroup(
            children: <Widget>[
              HtListItem(
                icon: Icons.verified_user_outlined,
                title: '隐私与数据',
                subtitle: demo ? '照片与形象只保存在本机' : '形象保存在本机；提交时发送照片',
                onTap: () => context.push('/privacy'),
              ),
              HtListItem(
                icon: Icons.storage_rounded,
                title: '存储空间',
                subtitle: avatarStorageSummary(library.avatars),
                onTap: () => context.push('/privacy'),
              ),
            ],
          ),
          const ListHeading('帮助'),
          HtListGroup(
            children: <Widget>[
              HtListItem(
                icon: Icons.photo_camera_outlined,
                title: '拍摄指南',
                onTap: () => context.push('/create/guide?mode=view'),
              ),
              HtListItem(
                icon: Icons.help_outline_rounded,
                title: '常见问题',
                onTap: () => context.push('/help'),
              ),
            ],
          ),
          const ListHeading('关于'),
          HtListGroup(
            children: <Widget>[
              HtListItem(
                icon: Icons.info_outline_rounded,
                title: '关于 HumanTwin AI',
                subtitle: '版本 $appVersion',
                onTap: () => context.push('/about'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'HumanTwin AI 不提供身体测量、健康或医疗分析。',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 隐私与数据: what is stored, where, for how long; auto-delete; clear all.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  late Future<int> _used = ref.read(localStoreProvider).usedBytes();

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final LibraryState library = ref.watch(libraryControllerProvider);
    final PhotoFlowState draft = ref.watch(photoFlowControllerProvider);
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final TextTheme text = Theme.of(context).textTheme;
    final int photoCopies =
        library.records.fold<int>(
          0,
          (int n, GenerationRecord r) => n + r.inputs.length,
        ) +
        draft.count;
    return Scaffold(
      appBar: const HtAppBar(title: '隐私与数据'),
      body: PageBody(
        children: <Widget>[
          const SizedBox(height: 8),
          HtCard(
            gradientBorder: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!isLargeText(context)) ...<Widget>[
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 28,
                    color: AppColors.accentPrimary,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('默认私密', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        demo
                            ? '你的照片和 3D 形象只保存在这台手机上，也不会进入系统备份。不需要账号，应用内没有统计分析。'
                            : '3D 形象保存在这台手机上。提交生成时，三张照片会发送到已配置的生成服务。不需要账号，应用内没有统计分析。',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: '保存在哪里、保留多久'),
          FactTable(
            rows: <FactRow>[
              FactRow(
                icon: Icons.image_outlined,
                label: '照片',
                value:
                    '本机。${settings.deleteInputCopies ? '生成完成后自动删除副本' : '照片副本随形象保存，直到你删除形象'}；草稿、待确认和未成功的记录会保留，移除记录时一起删除。从相册选择的原图不受影响；用相机拍摄的照片只在本应用中。',
              ),
              const FactRow(
                icon: Icons.view_in_ar_rounded,
                label: '形象',
                value: '本机应用私有存储，不进入系统备份，直到你删除。',
              ),
              const FactRow(
                icon: Icons.description_outlined,
                label: '记录',
                value: '本机，随形象一起删除。',
              ),
              const FactRow(
                icon: Icons.share_outlined,
                label: '已分享',
                value: '在接收方的设备上，本应用无法撤回。',
              ),
              demo
                  ? const FactRow(
                      icon: Icons.open_in_new_rounded,
                      label: '服务商',
                      value: '演示版不会上传任何内容。',
                    )
                  : const FactRow(
                      icon: Icons.open_in_new_rounded,
                      label: '服务商',
                      value: '照片和结果由已配置的生成服务按其政策处理（保留期限待确认）。',
                      tone: FactTone.warn,
                    ),
            ],
          ),
          const SizedBox(height: 16),
          HtListGroup(
            children: <Widget>[
              MergeSemantics(
                child: HtListItem(
                  icon: Icons.auto_delete_outlined,
                  title: '生成完成后自动删除照片副本',
                  subtitle: '关闭后，照片副本会随形象保存，直到你删除形象',
                  chevron: false,
                  onTap: () => ref
                      .read(appSettingsProvider.notifier)
                      .setDeleteInputCopies(!settings.deleteInputCopies),
                  trailing: Switch(
                    value: settings.deleteInputCopies,
                    onChanged: (bool value) => ref
                        .read(appSettingsProvider.notifier)
                        .setDeleteInputCopies(value),
                  ),
                ),
              ),
            ],
          ),
          SectionHeader(
            title: '存储空间',
            trailing: FutureBuilder<int>(
              future: _used,
              builder: (BuildContext context, AsyncSnapshot<int> snapshot) =>
                  Text(formatBytes(snapshot.data), style: text.bodyMedium),
            ),
          ),
          HtCard(
            child: Column(
              children: <Widget>[
                _row(text, '3D 形象', '${library.avatars.length} 个'),
                _row(text, '照片副本', '$photoCopies 张'),
                _row(text, '草稿', draft.isEmpty ? '0 个' : '1 个'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          HtListGroup(
            children: <Widget>[
              HtListItem(
                icon: Icons.delete_forever_outlined,
                title: '清除全部本机数据',
                subtitle: '删除所有形象、草稿、照片副本和记录',
                danger: true,
                onTap: () => _clearAll(library),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('完整隐私政策需在上线前由法务定稿。', style: text.bodySmall),
        ],
      ),
    );
  }

  Widget _row(TextTheme text, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: MergeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(
            value,
            style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    ),
  );

  Future<void> _clearAll(LibraryState library) async {
    final bool running =
        library.active.isNotEmpty || library.attention.isNotEmpty;
    final bool demo =
        ref.read(generationModeProvider) == GenerationMode.mock;
    final bool confirmed = await showHtConfirm(
      context,
      icon: Icons.warning_amber_rounded,
      title: '清除全部本机数据？',
      paragraphs: <String>[
        '将删除 ${library.avatars.length} 个形象、所有草稿、照片副本和任务记录，无法恢复。',
        '${running ? (demo ? '进行中的模拟任务会一起停止并删除。' : '仍在进行或待确认的生成任务不会因此停止，但本应用将无法再找回结果。') : ''}已经分享或导出的文件不会被撤回。',
      ],
      confirmLabel: '全部清除',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(libraryControllerProvider.notifier).clearAll();
    ref.read(shareControllerProvider.notifier).clear();
    if (!mounted) {
      return;
    }
    final Future<int> used = ref.read(localStoreProvider).usedBytes();
    setState(() {
      _used = used;
    });
    showHtSnack(context, '已清除全部本机数据');
  }
}

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final List<(String, String)> faq = <(String, String)>[
      if (demo) ('为什么所有形象看起来都一样？', '演示版的「生成」是模拟流程，结果都是同一个内置示例模型，并非根据你的照片重建。'),
      (
        '照片会上传吗？',
        demo
            ? '演示版不会上传任何照片。将来接入真实生成服务时，只有你确认提交后，三张照片才会发送给第三方服务，并会先单独征得你的同意。'
            : '会。只有你确认提交后，三张照片才会发送到已配置的生成服务。',
      ),
      ('生成需要多久？', demo ? '演示版约 5 秒。' : '耗时取决于生成服务，目前无法预估。你可以离开页面，稍后回来查看。'),
      ('离开页面会取消任务吗？', '不会。离开或「停止查询」只影响应用是否刷新进度，任务仍会继续。目前无法在应用内取消已提交的任务。'),
      (
        '什么是「待确认」？会重复扣费吗？',
        '照片发出后没有收到回复时，应用无法确定是否提交成功，因此不会自动重试。点「确认提交状态」核对时：如果之前已受理，会直接找回那次任务，不会重复扣费；如果之前没有受理，这一次会正式提交并使用 1 次额度。',
      ),
      ('删除形象后，已分享的文件会消失吗？', '不会。删除只影响这台手机，已经发出去的图片或文件由接收方保存。'),
      ('可以用来测量身材或做健康分析吗？', '不可以。形象仅供展示，不代表精确的身体数据，本应用不提供测量、健康或医疗功能。'),
      ('可以用别人的照片吗？', '请只使用你本人，或已获得本人同意的照片。'),
      (
        'GLB 文件怎么打开？',
        'GLB 是常见的 3D 文件格式，可以用 3D 查看器、Blender 等软件打开。部分聊天应用无法直接预览。',
      ),
    ];
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const HtAppBar(title: '常见问题'),
      body: PageBody(
        children: <Widget>[
          for (int i = 0; i < faq.length; i++)
            ExpansionTile(
              initiallyExpanded: i == 0,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              expandedAlignment: Alignment.centerLeft,
              shape: const Border(),
              collapsedShape: const Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
              title: Text(faq[i].$1, style: text.bodyLarge),
              children: <Widget>[Text(faq[i].$2, style: text.bodyMedium)],
            ),
          if (demo) ...<Widget>[
            const SizedBox(height: 16),
            HtListGroup(
              children: <Widget>[
                HtListItem(
                  icon: Icons.info_outline_rounded,
                  title: '关于演示版',
                  onTap: () => showDemoInfoSheet(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const HtAppBar(title: '关于'),
      body: PageBody(
        children: <Widget>[
          const SizedBox(height: 24),
          Center(
            child: Image.asset(
              'assets/images/brand/humantwin_mark.png',
              width: 72,
              height: 72,
              semanticLabel: 'HumanTwin AI 标志',
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: BrandLockup(showMark: false)),
          const SizedBox(height: 4),
          Center(
            child: Text('DIGITAL HUMAN · SMARTER LIFE', style: text.bodySmall),
          ),
          const SizedBox(height: 8),
          Center(child: Text('版本 $appVersion', style: text.bodyMedium)),
          if (demo) ...<Widget>[
            const SizedBox(height: 8),
            const Center(child: DemoChipButton()),
          ],
          const SectionHeader(title: '模型来源与第三方许可'),
          HtListGroup(
            children: <Widget>[
              const HtListItem(
                icon: Icons.view_in_ar_rounded,
                title: sampleModelAttribution,
                subtitle:
                    'MakeHuman 官方 CC0 人体基础 · Blender 体型、着装和材质处理 · 未使用用户照片',
              ),
              const HtListItem(
                icon: Icons.view_in_ar_rounded,
                title: '历史缓存示例模型 RiggedFigure',
                subtitle:
                    '© 2017 Cesium · Khronos glTF Sample Assets · CC BY 4.0',
              ),
              const HtListItem(
                icon: Icons.description_outlined,
                title: 'model-viewer',
                subtitle: 'Google LLC · BSD-3-Clause',
              ),
              HtListItem(
                icon: Icons.description_outlined,
                title: '开源组件',
                subtitle: 'Flutter 及依赖的开源许可',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'HumanTwin AI',
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'HumanTwin AI 生成的形象仅供展示，不代表精确的身体数据，不用于医疗、健康或测量用途。',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
