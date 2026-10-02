import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../home/home_screen.dart';
import 'avatar_actions.dart';
import 'generation_record.dart';
import 'library_controller.dart';
import 'record_widgets.dart';

enum _Filter { all, active, attention, done }

/// 我的形象: the private on-device library.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final LibraryState library = ref.watch(libraryControllerProvider);
    final List<GenerationRecord> tasks = library.libraryTasks;
    final List<GenerationRecord> avatars = library.avatars;
    final int total = tasks.length + avatars.length;
    final TextTheme text = Theme.of(context).textTheme;
    final AppBar appBar = AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: AppSpacing.gutter(context),
      title: Semantics(header: true, child: const Text('我的形象')),
    );
    if (total == 0) {
      return Scaffold(
        appBar: appBar,
        body: PageBody(
          children: <Widget>[
            EmptyState(
              title: '还没有形象',
              body: '创建完成的 3D 形象会保存在这台手机上，只有你能看到。',
              actions: <Widget>[
                PrimaryButton(
                  label: '创建第一个形象',
                  icon: Icons.add_rounded,
                  onPressed: () => startCreation(context, ref),
                ),
                LinkButton(
                  label: '先看看示例形象',
                  onPressed: () => context.push('/sample'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final List<GenerationRecord> active = tasks
        .where((GenerationRecord r) => r.info.group == StatusGroup.active)
        .toList();
    final List<GenerationRecord> attention = tasks
        .where((GenerationRecord r) => r.info.group == StatusGroup.attention)
        .toList();
    final Map<_Filter, int> counts = <_Filter, int>{
      _Filter.all: total,
      _Filter.active: active.length,
      _Filter.attention: attention.length,
      _Filter.done: avatars.length,
    };
    // A filter whose items all resolved falls back to 全部.
    final _Filter filter = counts[_filter]! > 0 ? _filter : _Filter.all;
    final List<GenerationRecord> shownTasks = switch (filter) {
      _Filter.all => <GenerationRecord>[...attention, ...active],
      _Filter.active => active,
      _Filter.attention => attention,
      _Filter.done => const <GenerationRecord>[],
    };
    final List<GenerationRecord> shownAvatars =
        filter == _Filter.all || filter == _Filter.done
        ? avatars
        : const <GenerationRecord>[];

    final DateTime now = ref.read(clockProvider)();
    final bool large = isLargeText(context);

    final List<Widget> cards = <Widget>[
      for (final GenerationRecord record in shownTasks)
        _TaskTile(record: record, now: now, large: large),
      for (final GenerationRecord record in shownAvatars)
        _AvatarTile(
          record: record,
          now: now,
          large: large,
          missing: library.missingFiles.contains(record.id),
        ),
    ];

    return Scaffold(
      appBar: appBar,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startCreation(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('创建'),
        tooltip: '创建新形象',
      ),
      body: PageBody(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: <Widget>[
                for (final MapEntry<_Filter, String> entry in <_Filter, String>{
                  _Filter.all: '全部',
                  _Filter.active: '进行中',
                  _Filter.attention: '需处理',
                  _Filter.done: '已完成',
                }.entries)
                  if (entry.key == _Filter.all ||
                      entry.key == _Filter.done ||
                      counts[entry.key]! > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${entry.value} ${counts[entry.key]}'),
                        selected: filter == entry.key,
                        onSelected: (_) => setState(() => _filter = entry.key),
                        selectedColor: AppColors.tonalBackground,
                        labelStyle: TextStyle(
                          color: filter == entry.key
                              ? AppColors.tonalForeground
                              : AppColors.textSecondary,
                          fontWeight: filter == entry.key
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: filter == entry.key
                              ? Colors.transparent
                              : AppColors.borderStrong,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '仅保存在本机 · 共 ${avatarStorageSummary(avatars)}',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cards.isEmpty)
            HtCard(
              child: Text(
                '没有符合条件的项目。',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
          else if (large)
            Column(
              children: <Widget>[
                for (final Widget card in cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: card,
                  ),
              ],
            )
          else
            // Two columns sized to their content (a fixed aspect ratio would clip larger text).
            Column(
              children: <Widget>[
                for (int i = 0; i < cards.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: cards[i]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: i + 1 < cards.length
                              ? cards[i + 1]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.record,
    required this.now,
    required this.large,
  });

  final GenerationRecord record;
  final DateTime now;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          record.name,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          maxLines: large ? 3 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '提交于 ${formatRecordTime(record.createdAt, now)}',
          style: text.bodySmall,
        ),
        if (large) ...<Widget>[
          const SizedBox(height: 4),
          RecordStatusChip(record: record),
        ],
      ],
    );
    return Semantics(
      button: true,
      label: '${record.name}，${recordStatusLabel(record)}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: () => context.push('/tasks/${record.id}'),
        child: large
            ? Row(
                children: <Widget>[
                  SizedBox(
                    width: 92,
                    child: TaskThumbnail(record: record, showChip: false),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: info),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TaskThumbnail(record: record),
                  const SizedBox(height: 8),
                  info,
                ],
              ),
      ),
    );
  }
}

class _AvatarTile extends ConsumerWidget {
  const _AvatarTile({
    required this.record,
    required this.now,
    required this.large,
    required this.missing,
  });

  final GenerationRecord record;
  final DateTime now;
  final bool large;
  final bool missing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> thumbChips = <Widget>[
      if (!record.resultSeen)
        const HtChip(label: '新', tone: ChipTone.info, onMedia: true),
      if (missing)
        const HtChip(
          label: '文件缺失',
          tone: ChipTone.warning,
          icon: Icons.image_not_supported_outlined,
          onMedia: true,
        ),
    ];
    void open() => context.push('/avatars/${record.id}');
    final String label =
        '${record.name}，${record.isSimulated ? '示例模型' : 'AI 生成'}${missing ? '，本机文件缺失' : ''}';
    final Widget meta = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              onTap: open,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      record.name,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: large ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatRecordTime(record.createdAt, now),
                      style: text.bodySmall,
                    ),
                    if (large) ...<Widget>[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          OriginBadge(
                            simulated: record.isSimulated,
                            short: true,
                          ),
                          if (missing)
                            const HtChip(label: '文件缺失', tone: ChipTone.warning),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '${record.name} 更多操作',
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () => showAvatarMenu(context, ref, record),
        ),
      ],
    );
    final Widget thumb = GestureDetector(
      onTap: open,
      onLongPress: () => showAvatarMenu(context, ref, record),
      child: ExcludeSemantics(
        child: AvatarThumbnail(
          record: record,
          top: large ? const <Widget>[] : thumbChips,
          showOrigin: !large,
        ),
      ),
    );
    return large
        ? Row(
            children: <Widget>[
              SizedBox(width: 92, child: thumb),
              const SizedBox(width: 16),
              Expanded(child: meta),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[thumb, const SizedBox(height: 8), meta],
          );
  }
}
