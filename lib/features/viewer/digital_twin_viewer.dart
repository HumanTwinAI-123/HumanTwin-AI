import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../app/theme/app_theme.dart';

typedef ModelViewerBuilder = Widget Function();

enum ViewerLifecycleEvent { pageReady, modelLoaded, modelError }

typedef ViewerBuilder =
    Widget Function(
      ValueChanged<Future<void> Function()> registerReload,
      ValueChanged<Future<bool> Function()> registerReadinessProbe,
      ValueChanged<ViewerLifecycleEvent> onLifecycleEvent,
    );

const String _viewerLifecycleChannelName = 'HumanTwinViewerLifecycle';
const String _viewerLifecycleSentinel = '__humanTwinViewerLifecycleInstalled';
const String _viewerLifecycleScript = r'''
(() => {
  const installedKey = '__humanTwinViewerLifecycleInstalled';
  if (window[installedKey] === true) {
    return;
  }
  window[installedKey] = true;

  const send = (message) => {
    const channel = window.HumanTwinViewerLifecycle;
    if (channel && typeof channel.postMessage === 'function') {
      channel.postMessage(message);
    }
  };

  window.addEventListener('load', () => send('page-ready'), {once: true});

  const modelViewer = document.querySelector('model-viewer');
  if (!modelViewer) {
    return;
  }
  modelViewer.addEventListener(
    'load',
    () => send('model-loaded'),
    {once: true},
  );
  modelViewer.addEventListener(
    'error',
    () => send('model-error'),
    {once: true},
  );
})();
''';

ModelViewer buildHumanModelViewer({
  String? poster,
  Color backgroundColor = const Color(0xFFDDE6F2),
  ValueChanged<Future<void> Function()>? onReloadReady,
  ValueChanged<Future<bool> Function()>? onReadinessProbeReady,
  ValueChanged<ViewerLifecycleEvent>? onLifecycleEvent,
}) {
  return ModelViewer(
    src: 'assets/models/human_demo.glb',
    alt: 'Synthetic human figure used to validate the 3D digital twin viewer',
    poster: poster,
    cameraControls: true,
    autoRotate: true,
    disableZoom: false,
    loading: Loading.eager,
    backgroundColor: backgroundColor,
    debugLogging: poster == null,
    relatedJs: _viewerLifecycleScript,
    javascriptChannels: <JavascriptChannel>{
      JavascriptChannel(
        _viewerLifecycleChannelName,
        onMessageReceived: (message) {
          final ViewerLifecycleEvent? event = _viewerLifecycleEventFromMessage(
            message.message,
          );
          if (event != null) {
            onLifecycleEvent?.call(event);
          }
        },
      ),
    },
    onWebViewCreated: (controller) {
      onReloadReady?.call(controller.reload);
      onReadinessProbeReady?.call(() async {
        try {
          final String? currentUrl = await controller.currentUrl();
          final Uri? uri = currentUrl == null ? null : Uri.tryParse(currentUrl);
          final bool isExpectedViewerPage =
              uri?.scheme == 'http' &&
              (uri?.host == '127.0.0.1' || uri?.host == 'localhost');
          if (!isExpectedViewerPage) {
            return false;
          }
          final Object result = await controller.runJavaScriptReturningResult(
            "window.$_viewerLifecycleSentinel === true && "
            "document.readyState === 'complete'",
          );
          return _isTrueJavaScriptResult(result);
        } on Object {
          return false;
        }
      });
    },
  );
}

ViewerLifecycleEvent? _viewerLifecycleEventFromMessage(String message) {
  return switch (message) {
    'page-ready' => ViewerLifecycleEvent.pageReady,
    'model-loaded' => ViewerLifecycleEvent.modelLoaded,
    'model-error' => ViewerLifecycleEvent.modelError,
    _ => null,
  };
}

bool _isTrueJavaScriptResult(Object result) {
  return result == true ||
      result == 1 ||
      result == 'true' ||
      result == '"true"';
}

class DigitalTwinViewerPage extends StatelessWidget {
  const DigitalTwinViewerPage({required this.modelViewerBuilder, super.key});

  final ModelViewerBuilder modelViewerBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('3D Digital Twin')),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              key: const ValueKey<String>('model-viewer-host'),
              child: modelViewerBuilder(),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE61B1F24),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Drag to rotate  •  Pinch to zoom  •  Auto-rotate on',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    this.viewerBuilder,
    this.watchdogDuration = const Duration(seconds: 8),
  });

  final ViewerBuilder? viewerBuilder;
  final Duration watchdogDuration;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  static const String _posterAsset = 'assets/images/viewer_poster.png';

  Future<void> Function()? _reloadAction;
  Future<bool> Function()? _readinessProbe;
  Timer? _watchdog;
  String? _posterDataUri;
  bool _posterPrepared = false;
  bool _isReloading = false;
  bool _exitSafe = false;
  bool _exitPending = false;
  bool _popCommitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.viewerBuilder != null) {
      _posterPrepared = true;
    } else {
      unawaited(_preparePoster());
    }
  }

  Future<void> _preparePoster() async {
    String? posterDataUri;
    try {
      final ByteData data = await rootBundle.load(_posterAsset);
      posterDataUri =
          'data:image/png;base64,${base64Encode(data.buffer.asUint8List())}';
    } on Object {
      posterDataUri = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _posterDataUri = posterDataUri;
      _posterPrepared = true;
    });
  }

  void _registerReload(Future<void> Function() reload) {
    if (!mounted) {
      return;
    }
    setState(() {
      _reloadAction = reload;
    });
  }

  void _registerReadinessProbe(Future<bool> Function() probe) {
    if (!mounted || _exitSafe) {
      return;
    }
    _readinessProbe = probe;
    _watchdog?.cancel();
    _watchdog = Timer(
      widget.watchdogDuration,
      () => unawaited(_runReadinessProbe()),
    );
  }

  Future<void> _runReadinessProbe() async {
    final Future<bool> Function()? probe = _readinessProbe;
    if (!mounted || _exitSafe || probe == null) {
      return;
    }
    bool pageReady = false;
    try {
      pageReady = await probe();
    } on Object {
      pageReady = false;
    }
    if (!mounted || _exitSafe) {
      return;
    }
    if (pageReady) {
      _markExitSafe(ViewerLifecycleEvent.pageReady);
    } else {
      debugPrint(
        'Viewer exit-safety watchdog could not confirm page readiness.',
      );
    }
  }

  void _markExitSafe(ViewerLifecycleEvent event) {
    if (!mounted || _exitSafe) {
      return;
    }
    _watchdog?.cancel();
    setState(() {
      _exitSafe = true;
    });
    if (_exitPending && !_popCommitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _exitSafe && _exitPending && !_popCommitted) {
          _performExit();
        }
      });
    }
  }

  void _requestExit() {
    if (!mounted || _popCommitted) {
      return;
    }
    if (!_exitSafe) {
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
    _returnFromViewer(context);
  }

  Future<void> _reload() async {
    final Future<void> Function()? reload = _reloadAction;
    if (reload == null || _isReloading) {
      return;
    }
    setState(() {
      _isReloading = true;
    });
    try {
      await reload();
    } on Object {
      // The existing WebView stays mounted so the user can try again.
    } finally {
      if (mounted) {
        setState(() {
          _isReloading = false;
        });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _exitSafe,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _popCommitted = true;
          return;
        }
        _requestExit();
      },
      child: Scaffold(
        key: const ValueKey<String>('viewer-screen'),
        body: ColoredBox(
          color: AppColors.background,
          child: Stack(
            children: <Widget>[
              const Positioned.fill(
                child: CustomPaint(painter: _ViewerGridPainter()),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            return SingleChildScrollView(
                              key: const ValueKey<String>('viewer-scroll'),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                20,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: math.max(
                                    0,
                                    constraints.maxHeight - 36,
                                  ),
                                ),
                                child: _buildContent(context),
                              ),
                            );
                          },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final bool showStepCount = MediaQuery.textScalerOf(context).scale(9) <= 13;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('viewer-back'),
              tooltip: '返回',
              onPressed: _requestExit,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface1,
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderSubtle),
                minimumSize: const Size.square(44),
                maximumSize: const Size.square(44),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                '数字人体',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (showStepCount)
              Text(
                '06 / 06',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: AppColors.textTertiary.withValues(alpha: 0.82),
                  fontFamily: 'monospace',
                  fontSize: 9,
                  height: 12 / 9,
                  letterSpacing: 0.25,
                ),
              ),
          ],
        ),
        Divider(
          height: 32,
          thickness: 1,
          color: AppColors.borderSubtle.withValues(alpha: 0.68),
        ),
        AspectRatio(
          aspectRatio: 358 / 590,
          child: DecoratedBox(
            key: const ValueKey<String>('viewer-canvas'),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadii.large),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x42000000),
                  offset: Offset(0, 14),
                  blurRadius: 32,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.large - 1),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RepaintBoundary(
                    key: const ValueKey<String>('viewer-host'),
                    child: _buildViewer(),
                  ),
                  const Positioned(
                    left: 18,
                    top: 16,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppColors.surface1,
                        child: Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Text(
                            'DIGITAL HUMAN · LOCAL MODEL',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              color: AppColors.accentPrimary,
                              fontFamily: 'monospace',
                              fontSize: 10,
                              height: 14 / 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ViewerControls(
          isReloadReady: _reloadAction != null,
          isReloading: _isReloading,
          onReload: () => unawaited(_reload()),
        ),
      ],
    );
  }

  Widget _buildViewer() {
    final ViewerBuilder? viewerBuilder = widget.viewerBuilder;
    if (viewerBuilder != null) {
      return viewerBuilder(
        _registerReload,
        _registerReadinessProbe,
        _markExitSafe,
      );
    }
    if (!_posterPrepared) {
      return Image.asset(
        _posterAsset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
    }
    return buildHumanModelViewer(
      poster: _posterDataUri,
      backgroundColor: AppColors.surface1,
      onReloadReady: _registerReload,
      onReadinessProbeReady: _registerReadinessProbe,
      onLifecycleEvent: _markExitSafe,
    );
  }
}

class _ViewerControls extends StatelessWidget {
  const _ViewerControls({
    required this.isReloadReady,
    required this.isReloading,
    required this.onReload,
  });

  final bool isReloadReady;
  final bool isReloading;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('viewer-controls'),
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accentPrimary,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: Color(0x2986D7FF), blurRadius: 18),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  '拖动旋转 · 双指缩放 · 自动旋转',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.surface2),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey<String>('viewer-reload'),
            onPressed: isReloadReady && !isReloading ? onReload : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              disabledForegroundColor: AppColors.textTertiary.withValues(
                alpha: 0.42,
              ),
              backgroundColor: AppColors.surface2,
              disabledBackgroundColor: AppColors.surface2.withValues(
                alpha: 0.42,
              ),
              side: BorderSide(
                color: isReloadReady
                    ? AppColors.borderSubtle
                    : AppColors.borderSubtle.withValues(alpha: 0.42),
              ),
              minimumSize: const Size(116, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
            ),
            icon: isReloading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}

class _ViewerGridPainter extends CustomPainter {
  const _ViewerGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _returnFromViewer(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go('/processing');
  }
}
