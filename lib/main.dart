import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/viewer/digital_twin_viewer.dart';

export 'features/viewer/digital_twin_viewer.dart'
    show DigitalTwinViewerPage, ModelViewerBuilder, buildHumanModelViewer;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(ProviderScope(child: HumanTwinApp()));
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
