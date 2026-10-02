import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/platform/device_services.dart';
import '../../shared/ui/ht_ui.dart';
import '../library/avatar_detail_screen.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import '../library/record_widgets.dart';
import 'share_controller.dart';
import 'share_files.dart';

enum ShareKind { image, file }

/// Exact preview before anything leaves the app (预览即所发).
class SharePreviewScreen extends ConsumerStatefulWidget {
  const SharePreviewScreen({
    required this.recordId,
    required this.kind,
    super.key,
  });

  final String recordId;
  final ShareKind kind;

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  bool _light = false;
  bool _brand = true;
  Uint8List? _png;
  PreparedExport? _prepared;
  bool _busy = true;
  bool _failed = false;
  bool _sending = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  GenerationRecord? get _record {
    if (widget.recordId == AvatarDetailScreen.sampleId) {
      return sampleRecord;
    }
    return ref.read(libraryControllerProvider).byId(widget.recordId);
  }

  Future<void> _prepare() async {
    final GenerationRecord? record = _record;
    if (record == null || !mounted) {
      return;
    }
    final int generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _png = null;
      _prepared = null;
    });
    try {
      final ShareController share = ref.read(shareControllerProvider.notifier);
      if (widget.kind == ShareKind.image) {
        final Uint8List png = await share.composeImage(
          record,
          light: _light,
          brand: _brand,
        );
        final PreparedExport prepared = await share.writeImage(record, png);
        if (!mounted || generation != _generation) {
          return;
        }
        setState(() {
          _png = png;
          _prepared = prepared;
          _busy = false;
        });
      } else {
        final PreparedExport prepared = await share.prepareModel(record);
        if (!mounted || generation != _generation) {
          return;
        }
        setState(() {
          _prepared = prepared;
          _busy = false;
        });
      }
    } on Object catch (error) {
      debugPrint('Export preparation failed: $error');
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _failed = true;
          _png = null;
          _prepared = null;
        });
      }
    }
  }

  Future<void> _share() async {
    final PreparedExport? prepared = _prepared;
    if (prepared == null || _sending || _busy || _failed) {
      return;
    }
    setState(() => _sending = true);
    final ShareOutcome outcome = await ref
        .read(deviceServicesProvider)
        .shareFile(prepared.file.path, mimeType: prepared.mimeType);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    showHtSnack(context, switch (outcome.status) {
      ShareStatus.handedOff when outcome.appLabel != null =>
        '已交给「${outcome.appLabel}」，请在该应用中完成发送',
      ShareStatus.handedOff => '已交给所选应用，请在该应用中完成发送',
      ShareStatus.closed => '已关闭分享面板',
      ShareStatus.failed => '无法打开分享面板，没有发送任何内容',
    });
  }

  Future<void> _save({required bool gallery}) async {
    final PreparedExport? prepared = _prepared;
    if (prepared == null || _sending || _busy || _failed) {
      return;
    }
    setState(() => _sending = true);
    final DeviceServices device = ref.read(deviceServicesProvider);
    final SaveOutcome outcome = gallery
        ? await device.saveImageToGallery(
            prepared.file.path,
            fileName: prepared.fileName,
          )
        : await device.saveDocument(
            prepared.file.path,
            fileName: prepared.fileName,
            mimeType: prepared.mimeType,
          );
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    showHtSnack(context, switch (outcome.status) {
      SaveStatus.saved => gallery ? '已保存到相册 · HumanTwin 文件夹' : '已保存到你选择的位置',
      SaveStatus.cancelled => '未保存，没有创建任何文件',
      SaveStatus.unsupported => '此设备不支持直接保存到相册，请使用「保存到文件…」',
      SaveStatus.failed => '保存失败，请检查目标位置是否留下未完整文件后重试',
    });
  }

  @override
  Widget build(BuildContext context) {
    final GenerationRecord? record =
        widget.recordId == AvatarDetailScreen.sampleId
        ? sampleRecord
        : watchRecord(ref, widget.recordId);
    final bool missing = ref.watch(
      libraryControllerProvider.select(
        (LibraryState s) => s.missingFiles.contains(widget.recordId),
      ),
    );
    if (record == null || !record.isDone || missing) {
      return Scaffold(
        appBar: const HtAppBar(title: '分享或导出', close: true),
        body: PageBody(
          children: <Widget>[
            EmptyState(
              title: '暂时无法导出',
              body: '这个形象的本机文件缺失，重新下载后才能分享或导出。',
              actions: <Widget>[
                PrimaryButton(
                  label: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return widget.kind == ShareKind.image
        ? _imagePreview(record)
        : _filePreview(record);
  }

  Widget _failureBanner(String title, String body) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: HtBanner(
      tone: BannerTone.danger,
      title: title,
      body: body,
      actions: <Widget>[LinkButton(label: '重试', onPressed: _prepare)],
    ),
  );

  Widget _imagePreview(GenerationRecord record) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool simulated = record.isSimulated;
    final Snapshot? snapshot = ref.watch(
      shareControllerProvider.select((ShareState s) => s.snapshots[record.id]),
    );
    final bool live = snapshot?.live ?? false;
    final bool galleryAvailable =
        defaultTargetPlatform == TargetPlatform.android &&
        ref.read(deviceSdkIntProvider) >= 29;
    final Uint8List? png = _png;
    return Scaffold(
      appBar: const HtAppBar(title: '预览图片', close: true),
      body: PageBody(
        children: <Widget>[
          const SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: AspectRatio(
                aspectRatio: 1080 / 1350,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0F14),
                    border: Border.all(color: AppColors.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: png != null
                      ? Image.memory(
                          png,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          semanticLabel:
                              '将要发送的图片：${record.name}，带有「${exportLabel(simulated: simulated)}」标注',
                        )
                      : Center(
                          child: _busy
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const SizedBox.square(
                                      dimension: 32,
                                      child: CircularProgressIndicator(),
                                    ),
                                    const SizedBox(height: 10),
                                    Text('正在生成图片…', style: text.bodyMedium),
                                  ],
                                )
                              : const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.textTertiary,
                                ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '这就是将要发送的图片 · 1080 × 1350 PNG${live ? ' · 当前视角' : ' · 固定视角'}',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (_failed)
            _failureBanner('图片生成失败', '没有发送任何内容。可以重试，或返回后重新加载 3D 模型。'),
          const SizedBox(height: 20),
          if (live) ...<Widget>[
            Text('背景', style: text.labelMedium),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('深色')),
                ButtonSegment<bool>(value: true, label: Text('浅灰')),
              ],
              selected: <bool>{_light},
              onSelectionChanged: (Set<bool> value) {
                setState(() => _light = value.first);
                unawaited(_prepare());
              },
            ),
            const SizedBox(height: 12),
          ],
          if (simulated)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('显示 HumanTwin 标识', style: text.bodyLarge),
              value: _brand,
              onChanged: (bool value) {
                setState(() => _brand = value);
                unawaited(_prepare());
              },
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '「${exportLabel(simulated: simulated)}」标注会保留在图片上，无法移除',
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FactTable(
            rows: <FactRow>[
              FactRow(
                icon: Icons.image_outlined,
                label: '包含',
                value:
                    '这张形象快照和标注；文件名 ${exportBaseName(record.name, simulated: record.isSimulated)}.png',
              ),
              FactRow(
                icon: Icons.verified_user_outlined,
                label: '不包含',
                value: '原始照片、位置信息、设备信息',
              ),
              FactRow(
                icon: Icons.share_outlined,
                label: '分享后',
                value: '对方可以保存和转发。之后删除这个形象，也不会撤回已发送的图片。',
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        children: <Widget>[
          ButtonPair(
            first: SecondaryButton(
              label: galleryAvailable ? '保存到相册' : '保存到文件…',
              icon: Icons.download_rounded,
              onPressed: _prepared == null || _busy || _failed || _sending
                  ? null
                  : () => _save(gallery: galleryAvailable),
            ),
            second: PrimaryButton(
              label: '分享…',
              icon: Icons.share_outlined,
              loading: _sending,
              onPressed: _prepared == null || _busy || _failed || _sending
                  ? null
                  : _share,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filePreview(GenerationRecord record) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool simulated = record.isSimulated;
    final PreparedExport? prepared = _prepared;
    final String fileName =
        '${exportBaseName(record.name, simulated: simulated)}.glb';
    return Scaffold(
      appBar: const HtAppBar(title: '导出 3D 文件', close: true),
      body: PageBody(
        children: <Widget>[
          const SizedBox(height: 8),
          HtCard(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: AvatarThumbnail(record: record, showOrigin: false),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        fileName,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'GLB · ${prepared == null ? '准备中…' : formatBytes(prepared.bytes)}',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      OriginBadge(
                        simulated: simulated,
                        short: true,
                        sample: record.id == AvatarDetailScreen.sampleId,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_failed)
            _failureBanner('文件准备失败', '没有发送任何内容。请重试；如果仍然失败，可能是本机文件已损坏。'),
          const SizedBox(height: 16),
          FactTable(
            rows: <FactRow>[
              FactRow(
                icon: Icons.view_in_ar_rounded,
                label: '包含',
                value:
                    '3D 模型副本（网格与材质不变），文件信息中加入「${simulated ? '示例模型' : 'AI 生成'}」标注',
              ),
              const FactRow(
                icon: Icons.verified_user_outlined,
                label: '不包含',
                value: '原始照片、位置信息、设备信息',
              ),
              if (simulated)
                const FactRow(
                  icon: Icons.description_outlined,
                  label: '署名',
                  value: '保留原模型的来源与许可信息，署名写入文件信息；本应用仅添加示例标注，不修改网格或材质',
                ),
              const FactRow(
                icon: Icons.share_outlined,
                label: '分享后',
                value: '对方可以保存和转发。之后删除这个形象，也不会撤回已发送的文件。',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const HtBanner(
            tone: BannerTone.neutral,
            body: '部分聊天应用可能无法预览 3D 文件，对方可能需要用 3D 查看器打开。',
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        children: <Widget>[
          ButtonPair(
            first: SecondaryButton(
              label: '保存到文件…',
              icon: Icons.folder_outlined,
              onPressed: prepared == null || _busy || _failed || _sending
                  ? null
                  : () => _save(gallery: false),
            ),
            second: PrimaryButton(
              label: '分享文件…',
              icon: Icons.share_outlined,
              loading: _sending,
              onPressed: prepared == null || _busy || _failed || _sending
                  ? null
                  : _share,
            ),
          ),
        ],
      ),
    );
  }
}
