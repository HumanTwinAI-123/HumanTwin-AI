import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../capture/photo_flow_controller.dart';
import '../common/info_sheets.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import '../library/record_widgets.dart';

/// Shown once per app session when leaving a running task.
bool _leaveHintShown = false;

/// 生成进度: one page per record. Opening it never submits anything.
class TaskScreen extends ConsumerStatefulWidget {
  const TaskScreen({required this.recordId, super.key});

  final String recordId;

  @override
  ConsumerState<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends ConsumerState<TaskScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final GenerationRecord? record = ref
          .read(libraryControllerProvider)
          .byId(widget.recordId);
      if (mounted && record?.info.group == StatusGroup.active) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  LibraryController get _library =>
      ref.read(libraryControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final GenerationRecord? record = watchRecord(ref, widget.recordId);
    if (record == null) {
      return Scaffold(
        appBar: const HtAppBar(title: '生成进度'),
        body: PageBody(
          children: <Widget>[
            EmptyState(
              title: '这条记录已移除',
              body: '可以在「我的形象」中查看其他形象。',
              actions: <Widget>[
                PrimaryButton(label: '返回首页', onPressed: () => context.go('/')),
              ],
            ),
          ],
        ),
      );
    }
    final StatusGroup group = record.info.group;
    return PopScope<Object?>(
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop && group == StatusGroup.active && !_leaveHintShown) {
          _leaveHintShown = true;
          showHtSnack(context, '任务会继续进行，可在首页或「我的形象」查看进度');
        }
      },
      child: Scaffold(
        appBar: HtAppBar(
          title: '生成进度',
          actions: <Widget>[
            if (group != StatusGroup.done)
              IconButton(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _showMenu(record),
              ),
          ],
        ),
        body: switch (group) {
          StatusGroup.active => _ActiveBody(record: record),
          StatusGroup.done => _DoneBody(record: record),
          StatusGroup.attention => _RecoveryBody(
            record: record,
            onTertiary: _tertiary,
          ),
        },
        bottomNavigationBar: BottomActionBar(children: _actions(record)),
      ),
    );
  }

  // ----------------------------------------------------------- actions

  List<Widget> _actions(GenerationRecord record) {
    final bool demo = record.mode == GenerationMode.mock;
    void home() => context.go('/');
    if (record.status != RecordStatus.done &&
        record.mode != ref.read(generationModeProvider)) {
      // Made by a build in the other mode: this build never runs or checks it.
      return <Widget>[
        TonalButton(
          label: '从本机移除',
          danger: true,
          onPressed: () => _remove(record),
        ),
        ActionHint(
          '这条记录由${demo ? '演示版' : '连接生成服务的版本'}创建，当前版本无法继续处理',
        ),
      ];
    }
    switch (record.status) {
      case RecordStatus.submitting ||
          RecordStatus.queued ||
          RecordStatus.processing ||
          RecordStatus.saving ||
          RecordStatus.checking:
        return <Widget>[
          SecondaryButton(label: '返回首页', onPressed: home),
          const ActionHint('可以离开此页面，任务不会因此取消'),
        ];
      case RecordStatus.done:
        return <Widget>[
          PrimaryButton(
            label: '查看形象',
            icon: Icons.view_in_ar_rounded,
            onPressed: () => context.go('/avatars/${record.id}'),
          ),
          LinkButton(label: '返回首页', onPressed: home),
        ];
      case RecordStatus.failed:
        return <Widget>[
          PrimaryButton(
            label: demo ? '重新模拟生成' : '使用新照片生成',
            onPressed: record.inputs.length == 3
                ? () => _newGeneration(record)
                : null,
          ),
          LinkButton(
            label: '查看拍摄建议',
            onPressed: () => context.push('/create/guide?mode=view'),
          ),
        ];
      case RecordStatus.rejected:
        return <Widget>[
          PrimaryButton(
            label: '更换照片',
            onPressed: () => _toDraft(record, '/create/photos'),
          ),
          LinkButton(
            label: '查看拍摄建议',
            onPressed: () => context.push('/create/guide?mode=view'),
          ),
        ];
      case RecordStatus.credits || RecordStatus.offline || RecordStatus.config:
        return <Widget>[
          PrimaryButton(label: '保存为草稿', onPressed: () => _toDraft(record, '/')),
          LinkButton(
            label: '检查后重新提交',
            onPressed: () => _toDraft(record, '/create/review'),
          ),
        ];
      case RecordStatus.timeout ||
          RecordStatus.paused ||
          RecordStatus.connection:
        return <Widget>[
          PrimaryButton(
            label: '继续查询',
            onPressed: () => _library.continuePolling(record.id),
          ),
          LinkButton(label: '返回首页', onPressed: home),
        ];
      case RecordStatus.downloadFailed:
        return <Widget>[
          PrimaryButton(
            label: '重新下载',
            icon: Icons.download_rounded,
            onPressed: () => _library.continuePolling(record.id),
          ),
          LinkButton(label: '返回首页', onPressed: home),
        ];
      case RecordStatus.unknown:
        return <Widget>[
          PrimaryButton(
            label: '确认提交状态',
            onPressed: () => _confirmSubmission(record),
          ),
          LinkButton(label: '稍后处理', onPressed: home),
        ];
      case RecordStatus.unresolved:
        return <Widget>[
          PrimaryButton(
            label: '复制记录编号',
            icon: Icons.content_copy_rounded,
            onPressed: () => _copyRef(record),
          ),
          LinkButton(label: '查看处理方法', onPressed: () => _unresolvedHelp(record)),
        ];
      case RecordStatus.lost:
        return <Widget>[
          PrimaryButton(
            label: '复制记录编号',
            icon: Icons.content_copy_rounded,
            onPressed: () => _copyRef(record),
          ),
          LinkButton(
            label: '从本机移除',
            danger: true,
            onPressed: () => _remove(record),
          ),
        ];
    }
  }

  void _tertiary(GenerationRecord record) {
    if (record.status == RecordStatus.unresolved) {
      _confirmSubmission(record);
    } else if (record.status == RecordStatus.failed) {
      _remove(record);
    }
  }

  Future<void> _copyRef(GenerationRecord record) async {
    await Clipboard.setData(ClipboardData(text: recordReference(record)));
    if (mounted) {
      showHtSnack(context, '已复制记录编号 ${recordReference(record)}');
    }
  }

  /// Asks before a non-empty draft is replaced; returns false if the user keeps it.
  Future<bool> _confirmReplaceDraft() async {
    if (ref.read(photoFlowControllerProvider).isEmpty) {
      return true;
    }
    return showHtConfirm(
      context,
      title: '替换当前草稿？',
      paragraphs: const <String>['首页还有一个未完成的草稿。继续会用这组照片替换它。'],
      confirmLabel: '替换草稿',
    );
  }

  /// Explains a restore that did not happen; returns true when the draft now holds the photos.
  bool _restoreSucceeded(DraftRestore result) {
    final String? message = switch (result) {
      DraftRestore.restored => null,
      DraftRestore.unavailable => '这组照片已不在本机，请重新选择照片',
      DraftRestore.draftNotEmpty => '当前草稿正在使用，请稍后再试',
      DraftRestore.failed => '照片没能放回草稿，请重试',
    };
    if (message != null) {
      showHtSnack(context, message);
    }
    return message == null;
  }

  /// Replaces the draft with this record's photos (asks before overwriting another draft).
  Future<void> _toDraft(GenerationRecord record, String then) async {
    if (!await _confirmReplaceDraft() || !mounted) {
      return;
    }
    final DraftRestore result = await _library.restoreToDraft(
      record.id,
      replaceExisting: true,
    );
    if (!mounted || !_restoreSucceeded(result)) {
      return;
    }
    if (then == '/') {
      context.go('/');
      showHtSnack(context, '已保存为草稿，可在首页继续');
    } else {
      context.go('/');
      unawaited(
        context.push(then == '/create/review' ? '/create/photos' : then),
      );
      if (then == '/create/review') {
        unawaited(context.push('/create/review'));
      }
    }
  }

  Future<void> _newGeneration(GenerationRecord record) async {
    final bool demo = record.mode == GenerationMode.mock;
    final bool go = await showHtConfirm(
      context,
      title: demo ? '重新模拟生成？' : '用新照片重新生成？',
      paragraphs: <String>[
        demo
            ? '会用同一组照片再次模拟，不上传照片，也不消耗额度。'
            : '同一组照片会被识别为同一次任务。请至少更换一张照片；提交时会再次使用 1 次生成额度。',
      ],
      confirmLabel: demo ? '重新模拟' : '选择照片',
    );
    if (!go || !mounted || !await _confirmReplaceDraft() || !mounted) {
      return;
    }
    final DraftRestore result = await _library.restoreToDraft(
      record.id,
      leaveEmpty: demo
          ? const <PhotoAngle>{}
          : const <PhotoAngle>{PhotoAngle.front},
      keepRecord: !demo,
      replaceExisting: true,
    );
    if (!mounted || !_restoreSucceeded(result)) {
      return;
    }
    context.go('/');
    unawaited(context.push('/create/photos'));
    if (demo) {
      unawaited(context.push('/create/review'));
    } else {
      showHtSnack(context, '请至少更换一张照片，再提交新的生成');
    }
  }

  Future<void> _confirmSubmission(GenerationRecord record) async {
    final bool go = await showHtConfirm(
      context,
      title: '核对之前的提交',
      paragraphs: const <String>[
        '应用会把同一组照片再次发给生成服务核对：',
        '· 如果之前已提交成功，会直接找回那次任务，不会重复扣费。',
        '· 如果之前没有提交成功，这一次会正式提交，并消耗 1 次生成额度。',
      ],
      confirmLabel: '核对（必要时提交）',
      cancelLabel: '暂不处理',
    );
    if (!go) {
      return;
    }
    final CheckOutcome outcome = await _library.confirmSubmission(record.id);
    if (!mounted) {
      return;
    }
    final String? message = switch (outcome) {
      CheckOutcome.bound => '核对完成：已关联到这组照片的生成任务',
      CheckOutcome.stillUnknown => '核对未完成，这次提交仍为「待确认」，请稍后再试',
      CheckOutcome.unresolved => '生成服务也无法确认，需要人工核实',
      CheckOutcome.nothingCreated => '之前的提交没有创建任务，也没有消耗额度',
      CheckOutcome.busy => '已有生成任务在进行中，完成后再核对',
      CheckOutcome.ignored => null,
    };
    if (message != null) {
      showHtSnack(context, message);
    }
  }

  Future<void> _remove(GenerationRecord record) async {
    final bool locked = unconfirmedStatuses.contains(record.status);
    final bool removed = await showHtConfirm(
      context,
      title: locked ? '移除待确认的记录？' : '移除这条生成记录？',
      paragraphs: <String>[removeRecordMessage(record)],
      confirmLabel: locked ? '仍要移除' : '移除',
      cancelLabel: '保留',
      destructive: true,
    );
    if (!removed || !mounted) {
      return;
    }
    final bool done = await _library.removeRecord(record.id);
    if (!mounted) {
      return;
    }
    if (!done) {
      showHtSnack(context, '正在提交，完成后才能移除');
      return;
    }
    context.go('/');
    showHtSnack(context, '已从本机移除这条记录');
  }

  void _unresolvedHelp(GenerationRecord record) {
    showHtSheet<void>(context, (BuildContext sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHeader(title: '如何处理「需人工核实」'),
          const SheetBody(
            child: Column(
              children: <Widget>[
                IconBullet(
                  icon: Icons.looks_one_outlined,
                  child: Text('复制记录编号。它能帮助服务管理员找到这次提交。'),
                ),
                IconBullet(
                  icon: Icons.looks_two_outlined,
                  child: Text('联系服务支持并提供记录编号。'),
                ),
                IconBullet(
                  icon: Icons.looks_3_outlined,
                  child: Text(
                    '如果管理员确认任务已存在，需要等管理员把任务关联到这条记录后才能找回；如果确认之前没有创建任务，点「再次检查」会正式提交并使用 1 次额度。',
                  ),
                ),
                HtBanner(
                  tone: BannerTone.neutral,
                  icon: Icons.lock_outline_rounded,
                  body: '除非你点「再次检查」，应用不会用这组照片再次发送请求。',
                ),
                SizedBox(height: 12),
              ],
            ),
          ),
          SheetBody(
            child: PrimaryButton(
              label: '复制记录编号',
              icon: Icons.content_copy_rounded,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _copyRef(record);
              },
            ),
          ),
        ],
      );
    });
  }

  void _showMenu(GenerationRecord record) {
    final bool demo = record.mode == GenerationMode.mock;
    final bool polling =
        !demo &&
        (record.status == RecordStatus.queued ||
            record.status == RecordStatus.processing);
    final bool locked = unconfirmedStatuses.contains(record.status);
    final bool inFlight =
        record.status == RecordStatus.submitting ||
        record.status == RecordStatus.checking;
    showHtSheet<void>(context, (BuildContext sheetContext) {
      void close() => Navigator.of(sheetContext).pop();
      // The sheet shows a snapshot; act only if the record is still in that state.
      bool unchanged() {
        final GenerationRecord? current = ref
            .read(libraryControllerProvider)
            .byId(record.id);
        if (current != null && current.status == record.status) {
          return true;
        }
        showHtSnack(context, '任务状态已更新，请重新查看');
        return false;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHeader(title: record.name, subtitle: recordStatusLabel(record)),
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: <Widget>[
                if (polling)
                  HtListItem(
                    icon: Icons.pause_rounded,
                    title: '停止查询进度',
                    subtitle: '任务仍会在生成服务中继续',
                    chevron: false,
                    onTap: () async {
                      close();
                      // The snackbar may outlive this page: keep the container, not the widget ref.
                      final ProviderContainer container =
                          ProviderScope.containerOf(context, listen: false);
                      final bool stopped = await _library.stopPolling(
                        record.id,
                      );
                      if (!mounted) {
                        return;
                      }
                      if (!stopped) {
                        showHtSnack(context, '任务状态已更新，请重新查看');
                        return;
                      }
                      showHtSnack(
                        context,
                        '已停止查询进度，生成服务仍在处理这次任务',
                        actionLabel: '继续查询',
                        onAction: () => container
                            .read(libraryControllerProvider.notifier)
                            .continuePolling(record.id),
                      );
                    },
                  ),
                HtListItem(
                  icon: Icons.help_outline_rounded,
                  title: '离开页面会取消任务吗？',
                  chevron: false,
                  onTap: () {
                    close();
                    _leaveHelp(demo);
                  },
                ),
                if (locked)
                  HtListItem(
                    icon: Icons.photo_camera_outlined,
                    title: '使用其他照片新建',
                    subtitle: '会作为新的提交，再次消耗额度',
                    chevron: false,
                    onTap: () async {
                      close();
                      if (!unchanged()) {
                        return;
                      }
                      final bool? go = await showHtChoice(
                        context,
                        title: '改用其他照片？',
                        paragraphs: const <String>[
                          '之前那次提交还没有确认，可能已经使用 1 次额度；它会继续保留在「需要你处理」中，可以随时核对。改用其他照片会作为新的提交，再次使用 1 次额度。',
                        ],
                        confirmLabel: '仍然新建',
                        cancelLabel: '先核对之前的提交',
                      );
                      if (!mounted || go == null) {
                        return;
                      }
                      if (go) {
                        context.go('/');
                        unawaited(context.push('/create/photos'));
                      } else {
                        unawaited(_confirmSubmission(record));
                      }
                    },
                  ),
                if (inFlight)
                  const HtListItem(
                    icon: Icons.lock_outline_rounded,
                    title: '请求进行中，暂不能移除',
                    subtitle: '等待服务回复后再操作，避免丢失这次提交',
                    chevron: false,
                  )
                else
                  HtListItem(
                    icon: Icons.delete_outline_rounded,
                    title: '从本机移除',
                    subtitle: removeRecordSubtitle(record),
                    danger: true,
                    chevron: false,
                    onTap: () {
                      close();
                      if (unchanged()) {
                        _remove(record);
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

  void _leaveHelp(bool demo) {
    showHtSheet<void>(context, (BuildContext sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHeader(title: '离开页面会取消任务吗？', subtitle: '不会。下面是几种操作的区别：'),
          SheetBody(
            child: FactTable(
              rows: <FactRow>[
                const FactRow(
                  icon: Icons.arrow_back_rounded,
                  label: '离开',
                  value: '返回首页或切到其他应用。任务继续进行，回来后自动更新进度。',
                ),
                FactRow(
                  icon: Icons.pause_rounded,
                  label: '停止查询',
                  value: demo
                      ? '模拟任务在本机进行，无需停止查询。'
                      : '应用不再查询进度，任务仍在生成服务中继续。可以随时「继续查询」。',
                ),
                FactRow(
                  icon: Icons.delete_outline_rounded,
                  label: '移除记录',
                  value: demo
                      ? '只删除这台手机上的记录。模拟任务不涉及服务端和额度。'
                      : '只删除这台手机上的记录；服务端任务不会停止，已使用的额度不会退回。',
                ),
                FactRow(
                  icon: Icons.close_rounded,
                  label: '取消任务',
                  value: demo
                      ? '模拟任务不涉及服务端和额度，移除记录即可。'
                      : '目前无法在应用内取消已提交的任务，也无法保证退回额度。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SheetBody(
            child: PrimaryButton(
              label: '知道了',
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ],
      );
    });
  }
}

/// 记录编号 shown for 需人工核实 / 记录丢失 (task id when known, else the local id) + submit time.
String recordReference(GenerationRecord record) {
  String two(int n) => n.toString().padLeft(2, '0');
  final DateTime t = record.createdAt;
  final String key = (record.taskId ?? record.id);
  final String short = key.length > 10 ? key.substring(key.length - 10) : key;
  return '$short · ${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

String removeRecordSubtitle(GenerationRecord record) {
  if (record.mode == GenerationMode.mock) {
    return '模拟任务，不涉及服务端和额度';
  }
  if (record.info.draftLike) {
    return '只删除本机记录；未创建任务，未消耗额度';
  }
  if (record.status == RecordStatus.failed) {
    return '只删除本机记录；额度是否退回以服务商规则为准';
  }
  return '不会停止服务端任务，也不会退还额度';
}

String removeRecordMessage(GenerationRecord record) {
  if (record.mode == GenerationMode.mock) {
    return '模拟任务的记录和照片副本会从本机删除，不涉及服务端和额度。';
  }
  if (unconfirmedStatuses.contains(record.status)) {
    return '之前的提交可能已被受理并使用了额度。移除会同时删除用于核对的照片副本，之后本应用将无法帮你找回这次任务。';
  }
  if (record.info.draftLike) {
    return '记录和照片副本会从本机删除。这次没有创建任务，也没有消耗额度。';
  }
  if (record.status == RecordStatus.failed) {
    return '记录和照片副本会从本机删除。移除不会影响额度，是否退回以服务商规则为准。';
  }
  return '记录和照片副本会从本机删除。生成服务不会因此停止这次任务，已使用的额度也不会退回；移除后，本应用将无法再查看这次的结果。';
}

// ------------------------------------------------------------------ bodies

class _OriginChip extends StatelessWidget {
  const _OriginChip({required this.record});

  final GenerationRecord record;

  @override
  Widget build(BuildContext context) {
    return record.mode == GenerationMode.mock
        ? const HtChip(
            label: '模拟生成 · 不上传照片',
            tone: ChipTone.sample,
            icon: Icons.view_in_ar_rounded,
          )
        : const HtChip(
            label: '生成服务',
            tone: ChipTone.ai,
            icon: Icons.auto_awesome_rounded,
          );
  }
}

class _ActiveBody extends ConsumerWidget {
  const _ActiveBody({required this.record});

  final GenerationRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool demo = record.mode == GenerationMode.mock;
    final (String title, String body) = switch (record.status) {
      RecordStatus.submitting when demo => ('正在准备模拟任务', '演示版不会上传照片，也不会产生费用。'),
      RecordStatus.submitting => (
        '正在提交照片',
        '正在把三张照片发送到生成服务，请保持应用打开。如果提交完成前应用被关闭，稍后需要先确认提交结果。',
      ),
      RecordStatus.queued => ('已提交，排队中', '生成服务正在安排处理。你可以离开此页面，任务会继续进行。'),
      RecordStatus.processing when demo => (
        '正在模拟生成',
        '演示版不会根据照片重建，完成后会得到示例模型。你可以离开此页面。',
      ),
      RecordStatus.processing => ('正在生成 3D 形象', '所需时间取决于生成服务。完成后会自动保存到「我的形象」。'),
      RecordStatus.saving =>
        demo
            ? ('正在保存', '正在保存到「我的形象」。')
            : ('生成完成，正在保存', '正在把 3D 模型下载到本机。下载不会重新生成。'),
      _ => ('正在核对之前的提交', '正在向生成服务核对这组照片是否已经提交，请稍候。'),
    };
    final Duration elapsed = ref
        .read(clockProvider)()
        .difference(record.createdAt);
    final String caption = demo
        ? '约需 5 秒'
        : record.status == RecordStatus.queued
        ? '排队时间取决于服务负载'
        : '已进行 ${elapsed.inMinutes} 分 ${elapsed.inSeconds % 60} 秒 · 无法预估剩余时间';
    return PageBody(
      children: <Widget>[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(
              color: AppColors.brandCyan.withValues(alpha: 0.22),
            ),
            gradient: RadialGradient(
              radius: 0.9,
              colors: <Color>[
                AppColors.brandCyan.withValues(alpha: 0.12),
                AppColors.surface1,
              ],
            ),
          ),
          child: Column(
            children: <Widget>[
              ProgressRing(
                progress: record.status == RecordStatus.processing
                    ? record.progress
                    : null,
                size: 128,
                stroke: 8,
              ),
              const SizedBox(height: 14),
              RecordStatusChip(record: record, large: true),
              const SizedBox(height: 8),
              Text(caption, style: text.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(children: <Widget>[_OriginChip(record: record)]),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, style: text.titleLarge),
        ),
        const SizedBox(height: 4),
        Text(body, style: text.bodyMedium),
        const SizedBox(height: 20),
        HtCard(child: StageList(stages: _stages(record))),
        _InfoCard(record: record),
      ],
    );
  }

  static List<Stage> _stages(GenerationRecord record) {
    final bool demo = record.mode == GenerationMode.mock;
    final List<String> titles = demo
        ? const <String>['准备', '模拟生成', '保存到「我的形象」']
        : const <String>['上传照片', '排队', '生成模型', '下载并保存到本机'];
    final int current = switch (record.status) {
      RecordStatus.submitting || RecordStatus.checking => 0,
      RecordStatus.queued => 1,
      RecordStatus.processing => demo ? 1 : 2,
      RecordStatus.saving => demo ? 2 : 3,
      _ => titles.length,
    };
    return <Stage>[
      for (int i = 0; i < titles.length; i++)
        Stage(
          titles[i],
          i < current
              ? StageState.done
              : i == current
              ? StageState.active
              : StageState.pending,
          subtitle:
              i == current &&
                  record.status == RecordStatus.processing &&
                  record.progress != null
              ? '${record.progress}%'
              : i == current && record.status == RecordStatus.checking
              ? '正在核对提交结果'
              : null,
        ),
    ];
  }
}

class _DoneBody extends ConsumerWidget {
  const _DoneBody({required this.record});

  final GenerationRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBody(
      children: <Widget>[
        StatusHero(
          tone: StatusTone.success,
          icon: Icons.check_circle_outline_rounded,
          title: '形象已保存',
          body: '「${record.name}」已保存到「我的形象」。',
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width * 0.55).clamp(140, 260),
            child: AvatarThumbnail(record: record),
          ),
        ),
        const SizedBox(height: 20),
        record.isSimulated
            ? const HtBanner(
                tone: BannerTone.sample,
                title: '这是示例模型',
                body: '演示版的生成过程是模拟的，结果并非根据你的照片重建。',
              )
            : const HtBanner(
                tone: BannerTone.info,
                icon: Icons.auto_awesome_rounded,
                title: 'AI 生成 · 仅供展示',
                body: '外观和比例可能与本人不同，不代表真实的身体尺寸。',
              ),
        _InfoCard(record: record),
      ],
    );
  }
}

class _RecoveryBody extends ConsumerWidget {
  const _RecoveryBody({required this.record, required this.onTertiary});

  final GenerationRecord record;
  final ValueChanged<GenerationRecord> onTertiary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final _Recovery spec = _recoverySpec(record);
    return PageBody(
      children: <Widget>[
        StatusHero(
          tone: spec.tone,
          icon: spec.icon,
          title: spec.title,
          body: spec.body,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            RecordStatusChip(record: record),
            _OriginChip(record: record),
          ],
        ),
        const SizedBox(height: 20),
        FactTable(rows: spec.facts),
        if (spec.note != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(spec.noteIcon, size: 16, color: spec.noteColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  spec.note!,
                  style: text.bodySmall?.copyWith(color: spec.noteColor),
                ),
              ),
            ],
          ),
        ],
        _InfoCard(record: record),
        if (spec.tertiary != null) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: LinkButton(
              label: spec.tertiary!,
              danger: record.status == RecordStatus.failed,
              onPressed: () => onTertiary(record),
            ),
          ),
          if (record.status == RecordStatus.unresolved)
            Text(
              '「再次检查」会再次发送同一组照片；若管理员确认之前没有创建任务，本次会正式提交并使用 1 次额度。',
              style: text.bodySmall?.copyWith(color: AppColors.warning),
              textAlign: TextAlign.center,
            ),
        ],
      ],
    );
  }
}

class _Recovery {
  const _Recovery({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    required this.facts,
    this.note,
    this.noteIcon = Icons.verified_user_outlined,
    this.noteColor = AppColors.success,
    this.tertiary,
  });

  final StatusTone tone;
  final IconData icon;
  final String title;
  final String body;
  final List<FactRow> facts;
  final String? note;
  final IconData noteIcon;
  final Color noteColor;
  final String? tertiary;
}

_Recovery _recoverySpec(GenerationRecord record) {
  final bool demo = record.mode == GenerationMode.mock;
  const FactRow notCreated = FactRow(
    icon: Icons.view_in_ar_rounded,
    label: '任务',
    value: '未创建',
    tone: FactTone.ok,
  );
  const FactRow notCharged = FactRow(
    icon: Icons.toll_outlined,
    label: '额度',
    value: '未消耗',
    tone: FactTone.ok,
  );
  const FactRow photosKept = FactRow(
    icon: Icons.image_outlined,
    label: '照片',
    value: '仍保存在本机',
  );
  const String readOnly = '只读取同一任务，不会创建新任务或再次扣费。';
  const String creates = '「检查后重新提交」会提交新的生成任务，提交前会再次确认。';
  final String progress = record.progress == null
      ? ''
      : '（上次进度 ${record.progress}%）';
  return switch (record.status) {
    RecordStatus.failed => _Recovery(
      tone: StatusTone.danger,
      icon: Icons.error_outline_rounded,
      title: '这次生成没有成功',
      body: demo ? '模拟任务未成功，不会产生任何费用。' : '生成服务未能完成这次任务。额度如何处理以服务商规则为准，本应用无法确认。',
      facts: <FactRow>[
        const FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '已结束，未生成模型',
          tone: FactTone.bad,
        ),
        demo
            ? const FactRow(
                icon: Icons.toll_outlined,
                label: '额度',
                value: '模拟任务，不消耗额度',
                tone: FactTone.ok,
              )
            : const FactRow(
                icon: Icons.toll_outlined,
                label: '额度',
                value: '以服务商规则为准',
                tone: FactTone.warn,
              ),
        photosKept,
      ],
      note: demo ? null : '「使用新照片生成」会提交新的生成任务，提交前会再次确认。',
      noteIcon: Icons.toll_outlined,
      noteColor: AppColors.warning,
      tertiary: '从本机移除',
    ),
    RecordStatus.rejected => const _Recovery(
      tone: StatusTone.danger,
      icon: Icons.image_not_supported_outlined,
      title: '照片未通过检查',
      body: '生成服务无法处理这组照片，没有创建生成任务。请参考拍摄建议更换照片。',
      facts: <FactRow>[
        notCreated,
        notCharged,
        FactRow(icon: Icons.image_outlined, label: '照片', value: '可以存为草稿后更换'),
      ],
    ),
    RecordStatus.timeout => _Recovery(
      tone: StatusTone.warning,
      icon: Icons.schedule_rounded,
      title: '生成时间较长',
      body: '任务仍在生成服务中进行，应用已暂停查询进度。继续查询只会读取同一任务的状态，不会重新提交。',
      facts: <FactRow>[
        FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '仍在进行$progress',
        ),
        const FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '已使用 1 次，继续查询不会再扣',
        ),
        photosKept,
      ],
      note: '「继续查询」$readOnly',
    ),
    RecordStatus.paused => _Recovery(
      tone: StatusTone.warning,
      icon: Icons.pause_rounded,
      title: '已停止查询进度',
      body: '生成服务仍在处理这次任务。随时可以继续查询，不会重新提交。',
      facts: <FactRow>[
        FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '仍在进行$progress',
        ),
        const FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '已使用 1 次，继续查询不会再扣',
        ),
      ],
      note: '「继续查询」$readOnly',
    ),
    RecordStatus.credits => const _Recovery(
      tone: StatusTone.warning,
      icon: Icons.toll_outlined,
      title: '生成额度不足',
      body: '生成服务当前额度不足，没有创建生成任务，也没有消耗额度。可以先保存为草稿，稍后再提交。',
      facts: <FactRow>[
        notCreated,
        notCharged,
        FactRow(icon: Icons.image_outlined, label: '照片', value: '已保存在本机'),
      ],
      note: creates,
      noteIcon: Icons.toll_outlined,
      noteColor: AppColors.warning,
    ),
    RecordStatus.offline => const _Recovery(
      tone: StatusTone.warning,
      icon: Icons.wifi_off_rounded,
      title: '暂时无法连接生成服务',
      body: '未能连接生成服务，照片未能发出，没有创建任务，也没有消耗额度。请检查网络后重新提交。',
      facts: <FactRow>[
        notCreated,
        notCharged,
        FactRow(icon: Icons.image_outlined, label: '照片', value: '已保存在本机'),
      ],
      note: creates,
      noteIcon: Icons.toll_outlined,
      noteColor: AppColors.warning,
    ),
    RecordStatus.config => const _Recovery(
      tone: StatusTone.warning,
      icon: Icons.warning_amber_rounded,
      title: '生成服务暂不可用',
      body: '生成服务的配置出现问题，没有创建任务，也没有消耗额度。这不是你的操作造成的，请稍后再试。',
      facts: <FactRow>[
        notCreated,
        notCharged,
        FactRow(icon: Icons.image_outlined, label: '照片', value: '已保存在本机'),
      ],
      note: creates,
      noteIcon: Icons.toll_outlined,
      noteColor: AppColors.warning,
    ),
    RecordStatus.connection => _Recovery(
      tone: StatusTone.warning,
      icon: Icons.wifi_off_rounded,
      title: '暂时无法获取进度',
      body: '任务已提交，生成服务会继续处理。网络恢复后可以继续查询，不会重新提交。',
      facts: <FactRow>[
        FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '已提交$progress',
        ),
        const FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '已使用 1 次，继续查询不会再扣',
        ),
        photosKept,
      ],
      note: '「继续查询」$readOnly',
    ),
    RecordStatus.unknown => const _Recovery(
      tone: StatusTone.warning,
      icon: Icons.help_outline_rounded,
      title: '未确认是否提交成功',
      body: '照片发出后没有收到服务回复，可能已经提交，也可能没有。为避免重复扣费，应用不会自动重新提交。',
      facts: <FactRow>[
        FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '无法确认是否已创建',
          tone: FactTone.warn,
        ),
        FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '若之前已受理，已使用 1 次，核对不会重复扣除；若之前未受理，核对时会正式提交并使用 1 次',
        ),
        FactRow(
          icon: Icons.lock_outline_rounded,
          label: '照片',
          value: '已锁定，用于核对这次提交',
        ),
      ],
      note: '「确认提交状态」会再次发送同一组照片：如果之前已受理，直接找回、不重复扣费；如果之前未受理，本次会正式提交并使用 1 次额度。',
      noteIcon: Icons.toll_outlined,
      noteColor: AppColors.warning,
    ),
    RecordStatus.unresolved => _Recovery(
      tone: StatusTone.warning,
      icon: Icons.person_outline_rounded,
      title: '提交结果需要人工核实',
      body: '生成服务无法确认这次提交是否成功。为避免重复扣费，这组照片已暂停提交，需要服务管理员核实后才能继续。',
      facts: <FactRow>[
        const FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '等待人工核实',
          tone: FactTone.warn,
        ),
        const FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '可能已使用 1 次',
        ),
        FactRow(
          icon: Icons.description_outlined,
          label: '编号',
          value: recordReference(record),
        ),
      ],
      tertiary: '再次检查',
    ),
    RecordStatus.downloadFailed => const _Recovery(
      tone: StatusTone.warning,
      icon: Icons.download_rounded,
      title: '模型下载失败',
      body: '生成已完成，但 3D 文件没有保存到本机。重新下载不会重新生成，也不会创建新任务。',
      facts: <FactRow>[
        FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '已完成',
          tone: FactTone.ok,
        ),
        FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '已使用 1 次，重新下载不会再扣',
        ),
        FactRow(
          icon: Icons.schedule_rounded,
          label: '期限',
          value: '服务商公开说明最多保留约 3 天，请尽快下载',
          tone: FactTone.warn,
        ),
      ],
      note: '「重新下载」$readOnly',
    ),
    _ => _Recovery(
      tone: StatusTone.danger,
      icon: Icons.image_not_supported_outlined,
      title: '找不到这次生成的记录',
      body: '生成服务没有这条任务的记录，可能已被重置。本应用已无法查询或下载这次结果。',
      facts: <FactRow>[
        const FactRow(
          icon: Icons.view_in_ar_rounded,
          label: '任务',
          value: '无法查询',
          tone: FactTone.warn,
        ),
        const FactRow(
          icon: Icons.toll_outlined,
          label: '额度',
          value: '可能已使用 1 次',
        ),
        FactRow(
          icon: Icons.description_outlined,
          label: '编号',
          value: recordReference(record),
        ),
      ],
    ),
  };
}

class _InfoCard extends ConsumerWidget {
  const _InfoCard({required this.record});

  final GenerationRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime now = ref.read(clockProvider)();
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: text.bodyMedium),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(title: '任务信息'),
        HtCard(
          child: Column(
            children: <Widget>[
              row('名称', record.name),
              row('提交时间', formatRecordTime(record.createdAt, now)),
              row(
                '生成方式',
                record.mode == GenerationMode.mock ? '模拟生成（演示版）' : '生成服务',
              ),
              if (record.taskId != null &&
                  record.mode == GenerationMode.service)
                row('任务编号', record.taskId!),
              if (record.recovered) row('核对结果', '已关联到这组照片的生成任务'),
            ],
          ),
        ),
      ],
    );
  }
}
