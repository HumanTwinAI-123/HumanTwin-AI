import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/storage/local_store.dart';
import '../../shared/ui/ht_ui.dart';
import '../generation/digital_twin_repository.dart';
import '../home/home_screen.dart';
import '../share/share_controller.dart';
import '../viewer/digital_twin_viewer.dart';
import 'avatar_actions.dart';
import 'generation_record.dart';
import 'library_controller.dart';
import 'record_widgets.dart';

/// 形象详情: interactive 3D view, origin label, metadata, rename, share/export and delete.
///
/// Keeps the v0.1 viewer's exit safety: back is held until the WebView page is confirmed ready
/// (lifecycle event or a positive readiness probe), and at most one pending exit is committed.
class AvatarDetailScreen extends ConsumerStatefulWidget {
  const AvatarDetailScreen({
    required this.recordId,
    this.viewerBuilder,
    this.watchdogDuration = const Duration(seconds: 8),
    super.key,
  });

  static const String sampleId = 'sample';

  final String recordId;

  /// Test hook replacing the WebView model viewer.
  final ViewerBuilder? viewerBuilder;
  final Duration watchdogDuration;

  @override
  ConsumerState<AvatarDetailScreen> createState() => _AvatarDetailScreenState();
}

/// The built-in sample shown from 「先看看示例形象」 (not a library item).
final GenerationRecord sampleRecord = GenerationRecord(
  id: AvatarDetailScreen.sampleId,
  name: '示例形象',
  createdAt: DateTime(2026, 10, 1),
  mode: GenerationMode.mock,
  status: RecordStatus.done,
  origin: ModelOrigin.simulatedSample,
  model: const ModelRef.asset(sampleModelAsset),
  modelBytes: 6396864,
  resultSeen: true,
);

class _AvatarDetailScreenState extends ConsumerState<AvatarDetailScreen> {
  Future<void> Function()? _reloadAction;
  Future<bool> Function()? _readinessProbe;
  ViewerScripts? _scripts;
  Timer? _watchdog;
  bool _isReloading = false;
  bool _exitSafe = false;
  bool _exitPending = false;
  bool _popCommitted = false;
  bool _modelLoaded = false;
  bool _modelError = false;
  bool _autoRotate = true;
  int _viewerGeneration = 0;
  bool _capturing = false;
  final Stopwatch _detailWatch = Stopwatch();
  final Stopwatch _loadWatch = Stopwatch();
  bool _hostCreatedLogged = false;

  bool get _isSample => widget.recordId == AvatarDetailScreen.sampleId;

  @override
  void initState() {
    super.initState();
    _detailWatch.start();
    _loadWatch.start();
    _traceViewer('detail');
    if (!_isSample) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          ref
              .read(libraryControllerProvider.notifier)
              .markSeen(widget.recordId),
        );
        if (GoRouterState.of(context).uri.queryParameters['redownload'] ==
            '1') {
          unawaited(_redownload());
        }
      });
    }
  }

  // ------------------------------------------------------- exit safety

  bool _isCurrentHost(int generation) =>
      mounted && !_popCommitted && generation == _viewerGeneration;

  void _traceViewer(String stage, {double? pageElapsedMs}) {
    if (kDebugMode) {
      debugPrint(
        'HT_VIEWER stage=$stage host=$_viewerGeneration '
        'detail_ms=${_detailWatch.elapsedMilliseconds} '
        'load_ms=${_loadWatch.elapsedMilliseconds}'
        '${pageElapsedMs == null ? '' : ' page_ms=$pageElapsedMs'}',
      );
    }
  }

  void _replaceViewerHost() {
    if (!mounted || _popCommitted) {
      return;
    }
    _watchdog?.cancel();
    _watchdog = null;
    setState(() {
      _viewerGeneration++;
      _reloadAction = null;
      _readinessProbe = null;
      _scripts = null;
      _exitSafe = false;
      _modelLoaded = false;
      _modelError = false;
      _isReloading = false;
      _hostCreatedLogged = false;
      _loadWatch.reset();
    });
    _traceViewer('host_replaced');
  }

  void _registerReload(int generation, Future<void> Function() reload) {
    if (!_isCurrentHost(generation)) {
      return;
    }
    if (!_hostCreatedLogged) {
      _hostCreatedLogged = true;
      _traceViewer('host_created');
    }
    setState(() => _reloadAction = reload);
  }

  void _registerReadinessProbe(int generation, Future<bool> Function() probe) {
    if (!_isCurrentHost(generation) || _exitSafe) {
      return;
    }
    _readinessProbe = probe;
    _watchdog?.cancel();
    _watchdog = Timer(
      widget.watchdogDuration,
      () => unawaited(_runReadinessProbe(generation)),
    );
  }

  Future<void> _runReadinessProbe(int generation) async {
    final Future<bool> Function()? probe = _readinessProbe;
    if (!_isCurrentHost(generation) || _exitSafe || probe == null) {
      return;
    }
    bool pageReady = false;
    try {
      pageReady = await probe();
    } on Object {
      pageReady = false;
    }
    if (!_isCurrentHost(generation) || _exitSafe) {
      return;
    }
    if (pageReady) {
      _traceViewer('probe_ready');
      _onLifecycle(generation, ViewerLifecycleEvent.pageReady);
    } else {
      debugPrint(
        'Viewer exit-safety watchdog could not confirm page readiness.',
      );
    }
  }

  void _onLifecycle(int generation, ViewerLifecycleEvent event) {
    if (!_isCurrentHost(generation)) {
      return;
    }
    if (event == ViewerLifecycleEvent.pageReady) {
      _traceViewer('page_ready');
    }
    if (event == ViewerLifecycleEvent.modelLoaded && !_modelLoaded) {
      _traceViewer('model_loaded');
      setState(() {
        _modelLoaded = true;
        _modelError = false;
      });
    } else if (event == ViewerLifecycleEvent.modelError && !_modelError) {
      setState(() => _modelError = true);
    }
    _markExitSafe(generation);
  }

  void _markExitSafe(int generation) {
    if (!_isCurrentHost(generation) || _exitSafe) {
      return;
    }
    _watchdog?.cancel();
    setState(() => _exitSafe = true);
    if (_exitPending && !_popCommitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrentHost(generation) && _exitSafe && _exitPending) {
          _performExit();
        }
      });
    }
  }

  void _requestExit() {
    if (!mounted || _popCommitted) {
      return;
    }
    if (!_exitSafe && _showsViewer) {
      _exitPending = true;
      return;
    }
    _performExit();
  }

  void _performExit() {
    if (!mounted || _popCommitted) {
      return;
    }
    _popCommitted = true;
    _exitPending = false;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _reload() async {
    final int generation = _viewerGeneration;
    final Future<void> Function()? reload = _reloadAction;
    if (_isReloading) {
      return;
    }
    if (reload == null) {
      // The viewer host failed before registering: rebuild it.
      _replaceViewerHost();
      return;
    }
    _loadWatch.reset();
    _traceViewer('reload');
    setState(() {
      _isReloading = true;
      _modelError = false;
      _modelLoaded = false;
    });
    try {
      await reload();
    } on Object {
      // The WebView stays mounted so the user can try again.
    } finally {
      if (_isCurrentHost(generation)) {
        setState(() => _isReloading = false);
      }
    }
  }

  @override
  void dispose() {
    _popCommitted = true;
    _watchdog?.cancel();
    _watchdog = null;
    _reloadAction = null;
    _readinessProbe = null;
    _scripts = null;
    _detailWatch.stop();
    _loadWatch.stop();
    super.dispose();
  }

  // ----------------------------------------------------------- actions

  bool _showsViewer = true;

  Future<void> _toggleAutoRotate() async {
    setState(() => _autoRotate = !_autoRotate);
    try {
      await _scripts?.run(
        "document.querySelector('model-viewer').autoRotate = $_autoRotate;",
      );
    } on Object {
      // The control still reflects the user's choice for the next load.
    }
  }

  Future<void> _resetView() async {
    try {
      await _scripts?.run(
        "(() => { const v = document.querySelector('model-viewer'); "
        "v.cameraOrbit = '20deg 80deg 140%'; v.fieldOfView = 'auto'; v.jumpCameraToGoal(); })();",
      );
    } on Object {
      // Ignore: the page may still be loading.
    }
  }

  Future<void> _redownload() async {
    final RedownloadOutcome outcome = await ref
        .read(libraryControllerProvider.notifier)
        .redownload(widget.recordId);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case RedownloadOutcome.restored:
        _replaceViewerHost();
        showHtSnack(context, '已重新下载到本机');
      case RedownloadOutcome.expired:
        showHtSnack(context, '无法重新下载：生成服务已不再提供这个文件');
      case RedownloadOutcome.failed:
        showHtSnack(context, '重新下载未完成，请稍后再试');
      case RedownloadOutcome.ignored:
        break;
    }
  }

  /// Captures the current view for the PNG export (falls back to the stored render).
  Future<void> _captureForShare(GenerationRecord record) async {
    setState(() => _capturing = true);
    await ref
        .read(shareControllerProvider.notifier)
        .captureSnapshot(record, scripts: _modelLoaded ? _scripts : null);
    if (mounted) {
      setState(() => _capturing = false);
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final GenerationRecord? stored = _isSample
        ? sampleRecord
        : watchRecord(ref, widget.recordId);
    if (stored == null || !stored.isDone) {
      return Scaffold(
        appBar: const HtAppBar(title: '形象'),
        body: PageBody(
          children: <Widget>[
            EmptyState(
              title: '这个形象已删除',
              body: '可以在「我的形象」查看其他形象。',
              actions: <Widget>[
                PrimaryButton(label: '返回', onPressed: () => context.pop()),
              ],
            ),
          ],
        ),
      );
    }
    final GenerationRecord record = stored;
    final LibraryState library = ref.watch(libraryControllerProvider);
    final bool missing = library.missingFiles.contains(record.id);
    final bool expired = library.expiredFiles.contains(record.id);
    final bool downloading = library.redownloading.contains(record.id);
    _showsViewer = !missing && !downloading;
    final TextTheme text = Theme.of(context).textTheme;

    return PopScope<Object?>(
      canPop: _exitSafe || !_showsViewer,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _popCommitted = true;
          return;
        }
        _requestExit();
      },
      child: Scaffold(
        key: const ValueKey<String>('viewer-screen'),
        appBar: HtAppBar(
          title: record.name,
          onBack: _requestExit,
          actions: <Widget>[
            if (!_isSample)
              IconButton(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _showMenu(record),
              ),
          ],
        ),
        body: PageBody(
          children: <Widget>[
            const SizedBox(height: 4),
            _viewerArea(
              record,
              missing: missing,
              expired: expired,
              downloading: downloading,
            ),
            const SizedBox(height: 16),
            _honesty(record),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(record.name, style: text.titleLarge),
                  ),
                ),
                if (!_isSample)
                  IconButton(
                    tooltip: '重命名',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showRenameDialog(context, ref, record),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _metadata(record, missing: missing, expired: expired),
            if (!_isSample && !missing) ...<Widget>[
              const SizedBox(height: 12),
              Center(
                child: LinkButton(
                  label: '删除这个形象',
                  danger: true,
                  onPressed: () => _delete(record),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          children: _bottom(
            record,
            missing: missing,
            expired: expired,
            downloading: downloading,
          ),
        ),
      ),
    );
  }

  List<Widget> _bottom(
    GenerationRecord record, {
    required bool missing,
    required bool expired,
    required bool downloading,
  }) {
    if (_isSample) {
      return <Widget>[
        PrimaryButton(
          label: '创建我的形象',
          icon: Icons.add_rounded,
          onPressed: () => startCreation(context, ref),
        ),
      ];
    }
    if (downloading) {
      return const <Widget>[
        PrimaryButton(label: '正在下载…', loading: true, onPressed: null),
      ];
    }
    if (missing && expired) {
      return <Widget>[
        TonalButton(
          label: '删除这个形象',
          danger: true,
          onPressed: () => _delete(record),
        ),
      ];
    }
    if (missing) {
      return <Widget>[
        PrimaryButton(
          label: '重新下载',
          icon: Icons.download_rounded,
          onPressed: _redownload,
        ),
        const ActionHint('只读取同一任务的模型，不会重新生成或扣费'),
      ];
    }
    return <Widget>[
      PrimaryButton(
        label: '分享或导出',
        icon: Icons.share_outlined,
        loading: _capturing,
        onPressed: () => showShareOptions(
          context,
          record,
          beforeImage: () => _captureForShare(record),
        ),
      ),
    ];
  }

  Future<void> _delete(GenerationRecord record) async {
    final bool deleted = await confirmDeleteAvatar(context, ref, record);
    if (deleted && mounted) {
      showHtSnack(context, '已删除「${record.name}」');
      _performExit();
    }
  }

  void _showMenu(GenerationRecord record) {
    showHtSheet<void>(context, (BuildContext sheetContext) {
      void close() => Navigator.of(sheetContext).pop();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHeader(title: record.name),
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: <Widget>[
                HtListItem(
                  icon: Icons.edit_outlined,
                  title: '重命名',
                  chevron: false,
                  onTap: () {
                    close();
                    showRenameDialog(context, ref, record);
                  },
                ),
                HtListItem(
                  icon: Icons.info_outline_rounded,
                  title: '详细信息',
                  chevron: false,
                  onTap: () {
                    close();
                    _showInfo(record);
                  },
                ),
                HtListItem(
                  icon: Icons.delete_outline_rounded,
                  title: '删除',
                  danger: true,
                  chevron: false,
                  onTap: () {
                    close();
                    _delete(record);
                  },
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  void _showInfo(GenerationRecord record) {
    final DateTime now = ref.read(clockProvider)();
    showHtSheet<void>(context, (BuildContext sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHeader(title: '详细信息'),
          SheetBody(
            child: _KeyValues(
              rows: <(String, String)>[
                ('名称', record.name),
                ('创建时间', formatRecordTime(record.createdAt, now)),
                (
                  '来源',
                  record.mode == GenerationMode.mock ? '模拟生成（演示版）' : '生成服务',
                ),
                ('结果类型', record.isSimulated ? '示例模型（非本人）' : 'AI 生成'),
                ('格式', 'GLB（glTF 二进制）'),
                ('大小', formatBytes(record.modelBytes)),
                ('保存位置', '应用私有存储，其他应用无法读取'),
                ('照片副本', record.inputs.isEmpty ? '生成完成后已自动删除' : '保留在本机'),
                if (record.taskId != null &&
                    record.mode == GenerationMode.service)
                  ('任务编号', record.taskId!),
              ],
            ),
          ),
          SheetBody(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '本应用不提供身体尺寸测量或健康分析。',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SheetBody(
            child: SecondaryButton(
              label: '关闭',
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ],
      );
    });
  }

  Widget _honesty(GenerationRecord record) {
    if (_isSample) {
      return const HtBanner(
        tone: BannerTone.sample,
        title: '内置示例模型',
        body: '用来预览 3D 查看效果，不是根据任何人的照片生成。',
      );
    }
    if (record.isSimulated) {
      return const HtBanner(
        tone: BannerTone.sample,
        title: '这是示例模型',
        body: '演示版的生成过程是模拟的，结果并非根据你的照片重建。',
      );
    }
    return const HtBanner(
      tone: BannerTone.info,
      icon: Icons.auto_awesome_rounded,
      title: 'AI 生成 · 仅供展示',
      body: '外观和比例可能与本人不同，不代表精确的身体数据。',
    );
  }

  Widget _metadata(
    GenerationRecord record, {
    required bool missing,
    required bool expired,
  }) {
    final DateTime now = ref.read(clockProvider)();
    return HtCard(
      child: _KeyValues(
        rows: <(String, String)>[
          ('创建时间', _isSample ? '内置' : formatRecordTime(record.createdAt, now)),
          (
            '来源',
            _isSample
                ? sampleModelAttribution
                : record.mode == GenerationMode.mock
                ? '模拟生成（演示版）'
                : '生成服务',
          ),
          ('文件', 'GLB · ${formatBytes(record.modelBytes)}'),
          ('保存位置', missing ? (expired ? '本机文件缺失' : '需重新下载') : '仅本机'),
          if (!_isSample) ('照片副本', record.inputs.isEmpty ? '已自动删除' : '保留在本机'),
        ],
      ),
    );
  }

  Widget _viewerArea(
    GenerationRecord record, {
    required bool missing,
    required bool expired,
    required bool downloading,
  }) {
    final double height = (MediaQuery.sizeOf(context).height * 0.54).clamp(
      260,
      460,
    );
    final TextTheme text = Theme.of(context).textTheme;
    Widget stateOverlay(
      Widget icon,
      String title,
      String body, {
      List<Widget> actions = const <Widget>[],
    }) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            key: const ValueKey<String>('viewer-state-scroll'),
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 48
                    ? constraints.maxHeight - 48
                    : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  icon,
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: text.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  ...actions,
                ],
              ),
            ),
          );
        },
      );
    }

    final List<Widget> layers = <Widget>[];
    if (downloading) {
      layers.add(
        stateOverlay(
          const SizedBox.square(
            dimension: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          '正在重新下载…',
          '只下载同一任务的模型，不会重新生成。',
        ),
      );
    } else if (missing) {
      layers.add(
        stateOverlay(
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.tint(AppColors.warning),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.image_not_supported_outlined,
              size: 34,
              color: AppColors.warning,
            ),
          ),
          expired ? '无法重新下载' : '本机模型文件已丢失',
          expired
              ? '生成服务已不再提供这个模型文件（服务商公开说明最多保留约 3 天）。之前导出或分享过的副本不受影响。'
              : '3D 文件不在这台手机上了，可能因清除应用数据、存储异常或写入中断而丢失。可以重新下载，不会重新生成。',
        ),
      );
    } else {
      layers.add(
        RepaintBoundary(
          key: const ValueKey<String>('viewer-host'),
          child: KeyedSubtree(
            key: ValueKey<int>(_viewerGeneration),
            child: _buildViewer(record),
          ),
        ),
      );
      if (_modelError) {
        layers.add(
          ColoredBox(
            color: const Color(0x8C0A0E14),
            child: stateOverlay(
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.error),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.view_in_ar_rounded,
                  size: 34,
                  color: AppColors.error,
                ),
              ),
              '3D 模型加载失败',
              '模型文件完好，可能是显示组件暂时出错。重新加载不会联网。',
              actions: <Widget>[
                const SizedBox(height: 12),
                TonalButton(
                  key: const ValueKey<String>('viewer-reload'),
                  label: '重新加载',
                  icon: Icons.refresh_rounded,
                  onPressed: _isReloading ? null : () => unawaited(_reload()),
                ),
              ],
            ),
          ),
        );
      } else if (!_modelLoaded) {
        layers.add(
          IgnorePointer(
            child: ColoredBox(
              color: const Color(0x8C0A0E14),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox.square(
                      dimension: 36,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '正在加载 3D 模型…',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        layers.add(
          const Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: IgnorePointer(
              child: Center(
                child: HtChip(
                  label: '拖动旋转 · 双指缩放',
                  icon: Icons.threesixty_rounded,
                  onMedia: true,
                ),
              ),
            ),
          ),
        );
      }
    }
    layers.add(
      Positioned(
        left: 12,
        top: 12,
        child: OriginBadge(
          simulated: record.isSimulated,
          onMedia: true,
          sample: _isSample,
        ),
      ),
    );
    if (!missing && !downloading && !_modelError) {
      layers.add(
        Positioned(
          right: 8,
          top: 8,
          child: Column(
            children: <Widget>[
              _OverlayButton(
                tooltip: _autoRotate ? '停止自动旋转' : '自动旋转',
                icon: _autoRotate
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: _toggleAutoRotate,
              ),
              const SizedBox(height: 8),
              _OverlayButton(
                tooltip: '重置视角',
                icon: Icons.center_focus_strong_rounded,
                onPressed: _resetView,
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey<String>('viewer-canvas'),
      height: height,
      decoration: BoxDecoration(
        gradient: viewerGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl - 1),
        child: Stack(fit: StackFit.expand, children: layers),
      ),
    );
  }

  Widget _buildViewer(GenerationRecord record) {
    final int generation = _viewerGeneration;
    void registerReload(Future<void> Function() reload) =>
        _registerReload(generation, reload);
    void registerProbe(Future<bool> Function() probe) =>
        _registerReadinessProbe(generation, probe);
    void onLifecycle(ViewerLifecycleEvent event) =>
        _onLifecycle(generation, event);

    final ViewerBuilder? viewerBuilder = widget.viewerBuilder;
    if (viewerBuilder != null) {
      return viewerBuilder(registerReload, registerProbe, onLifecycle);
    }
    final ModelRef? model = record.model;
    final String src = model == null
        ? sampleModelAsset
        : model.isAsset
        ? model.value
        : Uri.file(
            ref.read(localStoreProvider).file(model.value).path,
          ).toString();
    return buildHumanModelViewer(
      model: DigitalTwinModel(
        src: src,
        origin: record.origin ?? ModelOrigin.simulatedSample,
      ),
      backgroundColor: Colors.transparent,
      autoRotate: _autoRotate,
      cameraOrbit: '20deg 80deg 140%',
      onReloadReady: registerReload,
      onReadinessProbeReady: registerProbe,
      onLifecycleEvent: onLifecycle,
      onScriptsReady: (ViewerScripts scripts) {
        if (_isCurrentHost(generation)) {
          _scripts = scripts;
        }
      },
      onLoadTiming: (ViewerLoadTiming timing) {
        if (_isCurrentHost(generation)) {
          _traceViewer(timing.stage, pageElapsedMs: timing.pageElapsedMs);
        }
      },
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0x9E0D1117),
        side: const BorderSide(color: Color(0x24F2F5F8)),
      ),
      icon: Icon(icon),
    );
  }
}

class _KeyValues extends StatelessWidget {
  const _KeyValues({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool large = isLargeText(context);
    return Column(
      children: <Widget>[
        for (final (String label, String value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: MergeSemantics(
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(label, style: text.bodyMedium),
                        Text(
                          value,
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(label, style: text.bodyMedium),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            value,
                            textAlign: TextAlign.end,
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
