import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import 'app/app.dart';
import 'features/capture/photo_flow_controller.dart';
import 'features/generation/digital_twin_repository.dart';
import 'features/library/generation_record.dart';
import 'features/library/library_controller.dart';
import 'features/settings/app_settings.dart';
import 'shared/platform/device_services.dart';
import 'shared/storage/local_store.dart';
import 'features/viewer/digital_twin_viewer.dart';

export 'features/viewer/digital_twin_viewer.dart'
    show DigitalTwinViewerPage, ModelViewerBuilder, buildHumanModelViewer;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge with visible system bars (status bar shows time/battery); SafeArea handles insets.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final DeviceServices device = MethodChannelDeviceServices();
  DevicePaths paths;
  try {
    paths = await device.paths();
  } on Object catch (error) {
    // Without the platform channel (e.g. a host test) keep the app usable with throwaway storage.
    debugPrint('Device paths unavailable, using temporary storage: $error');
    final Directory temp = await Directory.systemTemp.createTemp('humantwin-');
    paths = DevicePaths(documents: temp.path, cache: temp.path, sdkInt: 0);
  }
  final LocalStore store = await LocalStore.open(
    documentsPath: paths.documents,
    cachePath: paths.cache,
  );
  final FileDraftPhotoStore drafts = FileDraftPhotoStore(
    store,
    // Upload builds enforce the service's JPEG/PNG ≤ 8 MB rule; Mock accepts common photos.
    strictFormats: () => humanTwinApiBaseUrl.isNotEmpty,
    cacheRoot: paths.pickerCache,
  );
  // Each piece of saved state loads independently: one unreadable file never blocks launch.
  final AppSettings settings = await _loadOr(
    'settings',
    () => AppSettings.load(store),
    const AppSettings(),
  );
  final List<GenerationRecord> records = await _loadOr(
    'records',
    () => LibraryController.loadRecords(store),
    const <GenerationRecord>[],
  );
  await _loadOr<void>('record cleanup', () async {
    if (await LibraryController.indexIntact(store)) {
      await LibraryController.sweepOrphans(store, records);
    } else {
      await LibraryController.preserveDamagedIndex(store);
    }
  }, null);
  await _loadOr<void>('draft cleanup', () async {
    if (await drafts.manifestIntact()) {
      await drafts.sweep();
    }
  }, null);
  final Map<PhotoAngle, XFile> draft = await _loadOr(
    'draft',
    drafts.load,
    const <PhotoAngle, XFile>{},
  );
  final PhotoAngle? pickingAngle = await _loadOr(
    'picking angle',
    drafts.pickingAngle,
    null,
  );

  runApp(
    ProviderScope(
      overrides: [
        deviceServicesProvider.overrideWithValue(device),
        deviceSdkIntProvider.overrideWithValue(paths.sdkInt),
        localStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings),
        draftPhotoStoreProvider.overrideWithValue(drafts),
        initialDraftProvider.overrideWithValue(draft),
        initialPickingAngleProvider.overrideWithValue(pickingAngle),
        initialRecordsProvider.overrideWithValue(records),
      ],
      child: HumanTwinApp(),
    ),
  );
}

Future<T> _loadOr<T>(String what, Future<T> Function() load, T fallback) async {
  try {
    return await load();
  } on Object catch (error) {
    debugPrint('Could not load $what: $error');
    return fallback;
  }
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
