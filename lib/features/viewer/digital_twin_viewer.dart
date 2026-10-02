import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../generation/digital_twin_repository.dart';

typedef ModelViewerBuilder = Widget Function();

enum ViewerLifecycleEvent { pageReady, modelLoaded, modelError }

typedef ViewerLoadTiming = ({String stage, double pageElapsedMs});

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

const String _viewerTimingScript = r'''
(() => {
  const viewer = document.querySelector('model-viewer');
  if (!viewer) {
    return;
  }
  const send = (stage, elapsed) => {
    const channel = window.HumanTwinViewerLifecycle;
    if (channel && Number.isFinite(elapsed)) {
      channel.postMessage(`timing:${stage}:${elapsed.toFixed(1)}`);
    }
  };
  viewer.addEventListener('load', () => {
    let modelResource;
    for (const entry of performance.getEntriesByType('resource')) {
      try {
        const url = new URL(entry.name, window.location.href);
        if (url.pathname === '/model' &&
            (url.hostname === '127.0.0.1' || url.hostname === 'localhost')) {
          modelResource = entry;
        }
      } catch (_) {
        // Only numeric timings are sent; resource URLs stay in the page.
      }
    }
    if (modelResource) {
      send('model-resource', modelResource.responseEnd);
    }
    requestAnimationFrame(() => requestAnimationFrame(() => {
      send('two-raf', performance.now());
    }));
  }, {once: true});
})();
''';

/// Accepts numeric, known debug stages only; never logs a resource URL or path.
@visibleForTesting
ViewerLoadTiming? viewerLoadTimingFromMessage(String message) {
  final List<String> parts = message.split(':');
  if (parts.length != 3 ||
      parts[0] != 'timing' ||
      !const <String>{'model-resource', 'two-raf'}.contains(parts[1])) {
    return null;
  }
  final double? elapsed = double.tryParse(parts[2]);
  if (elapsed == null || !elapsed.isFinite || elapsed < 0) {
    return null;
  }
  return (stage: parts[1], pageElapsedMs: elapsed);
}

/// Script access to the viewer page (auto-rotate, camera reset, snapshot capture).
class ViewerScripts {
  const ViewerScripts({required this.run, required this.evaluate});

  final Future<void> Function(String script) run;
  final Future<Object> Function(String script) evaluate;
}

ModelViewer buildHumanModelViewer({
  DigitalTwinModel model = DigitalTwinModel.sample,
  String? poster,
  Color backgroundColor = const Color(0xFFDDE6F2),
  bool autoRotate = true,
  String? cameraOrbit,
  ValueChanged<Future<void> Function()>? onReloadReady,
  ValueChanged<Future<bool> Function()>? onReadinessProbeReady,
  ValueChanged<ViewerLifecycleEvent>? onLifecycleEvent,
  ValueChanged<ViewerScripts>? onScriptsReady,
  ValueChanged<ViewerLoadTiming>? onLoadTiming,
}) {
  return ModelViewer(
    src: model.src,
    alt: model.origin == ModelOrigin.simulatedSample
        ? '示例 3D 模型，并非根据照片重建；可拖动旋转、双指缩放'
        : '生成服务返回的 3D 模型；可拖动旋转、双指缩放',
    poster: poster,
    cameraControls: true,
    autoRotate: autoRotate,
    cameraOrbit: cameraOrbit,
    disableZoom: false,
    loading: Loading.eager,
    backgroundColor: backgroundColor,
    debugLogging: false,
    relatedJs: kDebugMode
        ? '$_viewerLifecycleScript\n$_viewerTimingScript'
        : _viewerLifecycleScript,
    javascriptChannels: <JavascriptChannel>{
      JavascriptChannel(
        _viewerLifecycleChannelName,
        onMessageReceived: (message) {
          final ViewerLifecycleEvent? event = _viewerLifecycleEventFromMessage(
            message.message,
          );
          if (event != null) {
            onLifecycleEvent?.call(event);
          } else if (kDebugMode) {
            final ViewerLoadTiming? timing = viewerLoadTimingFromMessage(
              message.message,
            );
            if (timing != null) {
              onLoadTiming?.call(timing);
            }
          }
        },
      ),
    },
    onWebViewCreated: (controller) {
      onReloadReady?.call(controller.reload);
      onScriptsReady?.call(
        ViewerScripts(
          run: controller.runJavaScript,
          evaluate: controller.runJavaScriptReturningResult,
        ),
      );
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
