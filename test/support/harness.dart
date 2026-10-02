import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/app/app.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/library/library_controller.dart';
import 'package:human_twin_ai/features/settings/app_settings.dart';
import 'package:human_twin_ai/features/viewer/digital_twin_viewer.dart';
import 'package:human_twin_ai/shared/platform/device_services.dart';
import 'package:human_twin_ai/shared/storage/local_store.dart';
import 'package:image_picker/image_picker.dart';

/// In-memory store: widget tests run in fake async, where real file IO never completes.
class MemoryLocalStore extends LocalStore {
  MemoryLocalStore()
    : super(
        root: Directory('/memory/humantwin'),
        exportsDir: Directory('/memory/exports'),
      );

  final Map<String, Map<String, Object?>> files =
      <String, Map<String, Object?>>{};
  final List<String> deletedRecords = <String>[];
  int clears = 0;

  @override
  Future<Map<String, Object?>?> readJson(String name) async {
    final Map<String, Object?>? json = files[name];
    return json == null
        ? null
        : jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  }

  @override
  Future<void> writeJson(String name, Map<String, Object?> json) async {
    files[name] = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  }

  @override
  Future<void> deleteRecordDir(String id) async {
    recordDir(id);
    deletedRecords.add(id);
  }

  @override
  Future<void> deleteRecordFiles(String id, String folder) async {}

  @override
  Future<void> clearAll() async {
    clears++;
    files.clear();
  }

  @override
  Future<int> usedBytes() async => 2400000;

  Directory? _exports;
  int _exportCount = 0;

  /// Exports are real files (the share preview writes and the tests read them back).
  @override
  Future<File> exportFile(String fileName) async {
    Directory? root = _exports;
    if (root == null) {
      final Directory created = Directory.systemTemp.createTempSync(
        'ht-exports-',
      );
      addTearDown(() => created.deleteSync(recursive: true));
      root = _exports = created;
    }
    final Directory dir = Directory('${root.path}/${_exportCount++}')
      ..createSync();
    return File('${dir.path}/$fileName');
  }

  List<Object?> get savedRecords =>
      (files[LibraryController.fileName]?['records'] as List<Object?>?) ??
      const <Object?>[];
}

class FakeDeviceServices implements DeviceServices {
  FakeDeviceServices({
    this.share = const ShareOutcome(ShareStatus.handedOff, appLabel: '微信'),
    this.save = const SaveOutcome(SaveStatus.saved),
  });

  ShareOutcome share;
  SaveOutcome save;
  final List<String> calls = <String>[];

  @override
  Future<DevicePaths> paths() async =>
      const DevicePaths(documents: '/memory', cache: '/memory', sdkInt: 34);

  @override
  Future<ShareOutcome> shareFile(
    String path, {
    required String mimeType,
  }) async {
    calls.add('share $mimeType');
    return share;
  }

  @override
  Future<SaveOutcome> saveDocument(
    String path, {
    required String fileName,
    required String mimeType,
  }) async {
    calls.add('saveDocument $fileName');
    return save;
  }

  @override
  Future<SaveOutcome> saveImageToGallery(
    String path, {
    required String fileName,
  }) async {
    calls.add('saveImageToGallery $fileName');
    return save;
  }
}

/// Returns fake picks in order (paths are never read: the draft store is a passthrough).
class TestPicker extends ImagePicker {
  int picks = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    picks++;
    return XFile('/picked/photo-$picks.jpg');
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse.empty();
}

/// Drives the fake model viewer's lifecycle from a test.
class ViewerDriver {
  ViewerDriver({this.probeResult = false, this.reloadAction});

  final bool probeResult;
  final Future<void> Function()? reloadAction;
  ValueChanged<ViewerLifecycleEvent>? lifecycleCallback;
  int probeCalls = 0;
  int reloadCalls = 0;
  int builds = 0;

  Widget build(
    ValueChanged<Future<void> Function()> registerReload,
    ValueChanged<Future<bool> Function()> registerReadinessProbe,
    ValueChanged<ViewerLifecycleEvent> onLifecycleEvent,
  ) {
    builds++;
    lifecycleCallback = onLifecycleEvent;
    return FakeViewer(
      registerReload: registerReload,
      registerReadinessProbe: registerReadinessProbe,
      onReload: () async {
        reloadCalls++;
        await reloadAction?.call();
      },
      onProbe: () async {
        probeCalls++;
        return probeResult;
      },
    );
  }

  void send(ViewerLifecycleEvent event) => lifecycleCallback!(event);
}

class FakeViewer extends StatefulWidget {
  const FakeViewer({
    required this.registerReload,
    required this.registerReadinessProbe,
    required this.onReload,
    required this.onProbe,
    super.key,
  });

  final ValueChanged<Future<void> Function()> registerReload;
  final ValueChanged<Future<bool> Function()> registerReadinessProbe;
  final Future<void> Function() onReload;
  final Future<bool> Function() onProbe;

  @override
  State<FakeViewer> createState() => _FakeViewerState();
}

class _FakeViewerState extends State<FakeViewer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.registerReload(widget.onReload);
        widget.registerReadinessProbe(widget.onProbe);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey<String>('fake-viewer-content'),
    color: Colors.black,
  );
}

class TestApp {
  TestApp({
    required this.container,
    required this.store,
    required this.device,
    required this.picker,
    required this.repository,
    required this.viewer,
  });

  final ProviderContainer container;
  final MemoryLocalStore store;
  final FakeDeviceServices device;
  final TestPicker picker;
  final MockDigitalTwinRepository repository;
  final ViewerDriver viewer;

  LibraryState get library => container.read(libraryControllerProvider);
  PhotoFlowState get photos => container.read(photoFlowControllerProvider);
}

final DateTime testNow = DateTime(2026, 9, 30, 14, 30);

GenerationRecord doneRecord(
  String id, {
  String? name,
  GenerationMode mode = GenerationMode.mock,
  bool seen = true,
  DateTime? createdAt,
}) {
  return GenerationRecord(
    id: id,
    name: name ?? '示例形象 $id',
    createdAt: createdAt ?? DateTime(2026, 9, 30, 10),
    mode: mode,
    status: RecordStatus.done,
    taskId: 'mock-$id',
    origin: mode == GenerationMode.mock
        ? ModelOrigin.simulatedSample
        : ModelOrigin.serviceGenerated,
    model: const ModelRef.asset(sampleModelAsset),
    modelBytes: 50116,
    resultSeen: seen,
  );
}

/// Sets the logical screen size and system text scale for one test.
void configureView(WidgetTester tester, Size size, {double textScale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Pumps the full app (router, shell, every screen) on fakes: no WebView, no file IO.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  bool onboarded = true,
  bool showGuide = true,
  List<GenerationRecord> records = const <GenerationRecord>[],
  Map<PhotoAngle, XFile> draft = const <PhotoAngle, XFile>{},
  String initialLocation = '/',
  int sdkInt = 34,
  GenerationMode mode = GenerationMode.mock,
  Duration mockDelay = const Duration(seconds: 2),
  List<Override> overrides = const <Override>[],
}) async {
  final MemoryLocalStore store = MemoryLocalStore();
  final FakeDeviceServices device = FakeDeviceServices();
  final TestPicker picker = TestPicker();
  final MockDigitalTwinRepository repository = MockDigitalTwinRepository(
    delay: mockDelay,
  );
  final ViewerDriver viewer = ViewerDriver();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      deviceServicesProvider.overrideWithValue(device),
      deviceSdkIntProvider.overrideWithValue(sdkInt),
      imagePickerProvider.overrideWithValue(picker),
      lostDataRecoverySupportedProvider.overrideWithValue(false),
      digitalTwinRepositoryProvider.overrideWithValue(repository),
      generationModeProvider.overrideWithValue(mode),
      clockProvider.overrideWithValue(() => testNow),
      initialSettingsProvider.overrideWithValue(
        AppSettings(onboardingDone: onboarded, showGuide: showGuide),
      ),
      initialRecordsProvider.overrideWithValue(records),
      initialDraftProvider.overrideWithValue(draft),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: HumanTwinApp(
        viewerBuilder: viewer.build,
        initialLocation: initialLocation,
      ),
    ),
  );
  await settleFrames(tester);
  return TestApp(
    container: container,
    store: store,
    device: device,
    picker: picker,
    repository: repository,
    viewer: viewer,
  );
}

/// Advances route transitions without waiting for indefinite spinners to stop.
Future<void> settleFrames(WidgetTester tester, {int frames = 8}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets real async work (file IO, image codecs) finish between fake-async frames.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'condition not reached');
  await settleFrames(tester);
}

/// The page scroll view of [screen] (other tabs stay mounted offstage).
Finder scrollableIn(Type screen) => find
    .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
    .first;

/// Fails on any layout overflow or other framework exception collected so far.
void expectNoLayoutErrors(WidgetTester tester, String where) {
  final Object? error = tester.takeException();
  expect(error, isNull, reason: 'layout error on $where: $error');
}
