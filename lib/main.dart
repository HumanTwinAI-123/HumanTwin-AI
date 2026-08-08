import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

typedef ModelViewerBuilder = Widget Function();

void main() {
  runApp(const HumanTwinPocApp());
}

class HumanTwinPocApp extends StatelessWidget {
  const HumanTwinPocApp({
    super.key,
    this.modelViewerBuilder = buildHumanModelViewer,
  });

  final ModelViewerBuilder modelViewerBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HumanTwin AI 3D POC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B5BDB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: ViewerLauncherPage(modelViewerBuilder: modelViewerBuilder),
    );
  }
}

class ViewerLauncherPage extends StatelessWidget {
  const ViewerLauncherPage({required this.modelViewerBuilder, super.key});

  final ModelViewerBuilder modelViewerBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HumanTwin AI 3D POC')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.view_in_ar_rounded,
                    size: 88,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Validate the 3D viewer',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Open the bundled GLB model and verify rotation, zoom, '
                    'auto-rotate, and repeat entry on Android.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    key: const ValueKey<String>('open-viewer-button'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              DigitalTwinViewerPage(
                                modelViewerBuilder: modelViewerBuilder,
                              ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Open 3D Viewer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

ModelViewer buildHumanModelViewer() {
  return const ModelViewer(
    src: 'assets/models/human_demo.glb',
    alt: 'Synthetic human figure used to validate the 3D digital twin viewer',
    cameraControls: true,
    autoRotate: true,
    disableZoom: false,
    loading: Loading.eager,
    backgroundColor: Color(0xFFDDE6F2),
  );
}
