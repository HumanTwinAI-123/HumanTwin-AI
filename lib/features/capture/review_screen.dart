import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../common/info_sheets.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import 'photo_flow_controller.dart';
import 'photo_selection_screen.dart';

/// 检查并提交 (step 3/3): the single, explicit place a generation starts.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(libraryControllerProvider.notifier).suggestName(),
  );
  bool _selfConsent = false;
  bool _newDespiteUnconfirmed = false;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bool demo = ref.read(generationModeProvider) == GenerationMode.mock;
    if (!demo) {
      // Developer service builds still confirm before sending photos to the configured service.
      final bool confirmed = await _confirmUpload(context);
      if (!confirmed || !mounted) {
        return;
      }
    }
    setState(() => _submitting = true);
    final SubmitResult result = await ref
        .read(libraryControllerProvider.notifier)
        .submit(name: _name.text, allowWithUnconfirmed: _newDespiteUnconfirmed);
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    final String? id = result.id;
    if (id != null) {
      // Creation pages leave the stack: back from progress goes to 首页, never back to submit.
      context.go('/tasks/$id');
      return;
    }
    showHtSnack(context, switch (result.block) {
      SubmitBlock.busy => '已有生成任务在进行中，完成后再提交',
      SubmitBlock.unconfirmed => '请先处理尚未确认的提交',
      SubmitBlock.storage => '无法保存到这台手机，请检查存储空间后重试',
      _ => '请先补齐三张照片',
    });
  }

  @override
  Widget build(BuildContext context) {
    final PhotoFlowState photos = ref.watch(photoFlowControllerProvider);
    final LibraryState library = ref.watch(libraryControllerProvider);
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final TextTheme text = Theme.of(context).textTheme;
    final String? nameError = validateRecordName(_name.text);
    // Only this build's mode counts, exactly as LibraryController.submit decides.
    final GenerationMode mode = ref.watch(generationModeProvider);
    final List<GenerationRecord> blocking = library.blocking
        .where((GenerationRecord r) => r.mode == mode)
        .toList();
    final List<GenerationRecord> unconfirmed = library.unconfirmed
        .where((GenerationRecord r) => r.mode == mode)
        .toList();
    final bool needsChoice = unconfirmed.isNotEmpty && !_newDespiteUnconfirmed;
    final bool photosOk = photos.isComplete && !photos.isPicking;
    final bool canSubmit =
        photosOk &&
        nameError == null &&
        blocking.isEmpty &&
        !needsChoice &&
        (demo || _selfConsent) &&
        !_submitting;
    final bool keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: const HtAppBar(title: '检查并提交', step: (3, 3)),
      body: PageBody(
        children: <Widget>[
          const SizedBox(height: 8),
          Text('照片', style: text.titleMedium),
          const SizedBox(height: 12),
          PhotoSlots(photos: photos, allowDelete: false),
          if (!photos.isComplete) ...<Widget>[
            const SizedBox(height: 12),
            const HtBanner(
              tone: BannerTone.danger,
              title: '照片还不完整',
              body: '请为每个位置选择一张可用的照片。',
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey<String>('review-name'),
            controller: _name,
            maxLength: 20,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '形象名称',
              helperText: '之后也可以重命名',
              errorText: nameError,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SectionHeader(title: '接下来会发生什么'),
          HtCard(
            child: Column(
              children: demo
                  ? const <Widget>[
                      IconBullet(
                        icon: Icons.hourglass_empty_rounded,
                        child: Text('模拟生成约 5 秒，不会上传照片，也不消耗额度。'),
                      ),
                      IconBullet(
                        icon: Icons.view_in_ar_rounded,
                        child: Text('完成后得到示例模型，并非根据你的照片重建。'),
                      ),
                      IconBullet(
                        icon: Icons.lock_outline_rounded,
                        child: Text('结果保存在这台手机上的「我的形象」。'),
                      ),
                    ]
                  : const <Widget>[
                      IconBullet(
                        icon: Icons.upload_rounded,
                        child: Text('三张照片将发送到当前配置的生成服务处理。'),
                      ),
                      IconBullet(
                        icon: Icons.schedule_rounded,
                        child: Text('耗时取决于生成服务，可以离开此页面，任务会继续。'),
                      ),
                      IconBullet(
                        icon: Icons.info_outline_rounded,
                        child: Text('结果仅供展示，不代表精确的身体数据。'),
                      ),
                    ],
            ),
          ),
          if (!demo)
            CheckboxListTile(
              value: _selfConsent,
              onChanged: (bool? value) =>
                  setState(() => _selfConsent = value ?? false),
              title: Text(
                '照片中是我本人，或我已获得本人同意',
                style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          if (blocking.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            HtBanner(
              tone: BannerTone.warning,
              title: '已有 1 个生成任务未结束',
              body: '一次只能进行一个生成任务。这组照片已保存为草稿，之前的任务完成或移除后可以回来提交。',
              actions: <Widget>[
                LinkButton(
                  label: '查看那个任务',
                  onPressed: () => context.push('/tasks/${blocking.first.id}'),
                ),
              ],
            ),
          ] else if (needsChoice) ...<Widget>[
            const SizedBox(height: 16),
            HtBanner(
              tone: BannerTone.warning,
              title: '有 1 次提交尚未确认',
              body: '之前那次可能已经受理并使用了额度。建议先核对，再决定是否新建。',
              actions: <Widget>[
                LinkButton(
                  label: '先核对之前的提交',
                  onPressed: () =>
                      context.push('/tasks/${unconfirmed.first.id}'),
                ),
                LinkButton(
                  label: '仍然新建',
                  onPressed: () async {
                    final bool confirmed = await showHtConfirm(
                      context,
                      title: '仍然新建一次生成？',
                      paragraphs: const <String>[
                        '之前那次提交还没有确认，可能已经使用 1 次额度；它会继续保留在「需要你处理」中，可以随时核对。新建会作为新的提交，再次使用 1 次额度。',
                      ],
                      confirmLabel: '仍然新建',
                    );
                    if (confirmed) {
                      setState(() => _newDespiteUnconfirmed = true);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : BottomActionBar(
              children: <Widget>[
                PrimaryButton(
                  label: demo ? '开始模拟生成' : '提交生成',
                  icon: demo ? null : Icons.upload_rounded,
                  loading: _submitting,
                  onPressed: canSubmit ? _submit : null,
                ),
                ActionHint(demo ? '提交后可在首页和「我的形象」查看进度' : '提交前会再次确认上传'),
              ],
            ),
    );
  }
}

/// Short confirmation before photos leave the device (service builds only).
Future<bool> _confirmUpload(BuildContext context) async {
  final bool? confirmed = await showHtSheet<bool>(context, (
    BuildContext sheetContext,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(title: '提交前请确认'),
        const SheetBody(
          child: Column(
            children: <Widget>[
              IconBullet(
                icon: Icons.upload_rounded,
                child: Text('三张照片将发送到当前配置的生成服务处理。'),
              ),
              IconBullet(
                icon: Icons.info_outline_rounded,
                child: Text('提交后无法在应用内取消；生成结果仅供展示，不代表精确的身体数据。'),
              ),
            ],
          ),
        ),
        SheetBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PrimaryButton(
                label: '确认提交',
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              LinkButton(
                label: '再检查一下',
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  });
  return confirmed ?? false;
}
