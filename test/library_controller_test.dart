import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_twin_ai/features/capture/photo_flow_controller.dart';
import 'package:human_twin_ai/features/generation/digital_twin_repository.dart';
import 'package:human_twin_ai/features/library/generation_record.dart';
import 'package:human_twin_ai/features/library/library_controller.dart';
import 'package:human_twin_ai/features/settings/app_settings.dart';
import 'package:human_twin_ai/shared/storage/local_store.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FlakyStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ht-library-');
    final LocalStore opened = await LocalStore.open(
      documentsPath: '${temp.path}/docs',
      cachePath: '${temp.path}/cache',
    );
    store = FlakyStore(root: opened.root, exportsDir: opened.exportsDir);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  File jpeg(String name) {
    final File file = File('${temp.path}/$name.jpg')
      ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6, 7, 8]);
    return file;
  }

  ({ProviderContainer container, ScriptedRepository repo}) setup({
    GenerationMode mode = GenerationMode.service,
    List<GenerationRecord> records = const <GenerationRecord>[],
    bool deleteInputs = true,
  }) {
    final ScriptedRepository repo = ScriptedRepository();
    final FakePicker picker = FakePicker(<XFile>[
      XFile(jpeg('front').path),
      XFile(jpeg('side').path),
      XFile(jpeg('back').path),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        digitalTwinRepositoryProvider.overrideWithValue(repo),
        generationModeProvider.overrideWithValue(mode),
        imagePickerProvider.overrideWithValue(picker),
        lostDataRecoverySupportedProvider.overrideWithValue(false),
        draftPhotoStoreProvider.overrideWithValue(
          FileDraftPhotoStore(store, strictFormats: () => false),
        ),
        initialRecordsProvider.overrideWithValue(records),
        initialSettingsProvider.overrideWithValue(
          AppSettings(onboardingDone: true, deleteInputCopies: deleteInputs),
        ),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 30, 13, 5)),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, repo: repo);
  }

  Future<void> pickAll(ProviderContainer container) async {
    final PhotoFlowController photos = container.read(
      photoFlowControllerProvider.notifier,
    );
    for (final PhotoAngle angle in PhotoAngle.values) {
      await photos.select(angle, source: ImageSource.gallery);
    }
    expect(container.read(photoFlowControllerProvider).isComplete, isTrue);
  }

  Future<void> settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  LibraryState library(ProviderContainer c) =>
      c.read(libraryControllerProvider);
  LibraryController controller(ProviderContainer c) =>
      c.read(libraryControllerProvider.notifier);

  test(
    'submit hands off the draft, creates once, and saves the sample result',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup(
        mode: GenerationMode.mock,
      );
      await pickAll(container);

      final SubmitResult result = await controller(
        container,
      ).submit(name: ' 示例形象 9月30日 ');
      final String id = result.id!;
      expect(container.read(photoFlowControllerProvider).isEmpty, isTrue);
      expect(library(container).byId(id)!.status, RecordStatus.submitting);
      expect(library(container).byId(id)!.name, '示例形象 9月30日');

      await settle();
      final GenerationRecord done = library(container).byId(id)!;
      expect(repo.creates, 1);
      expect(done.status, RecordStatus.done);
      expect(done.model, const ModelRef.asset(sampleModelAsset));
      expect(
        done.inputs,
        isEmpty,
        reason: 'photo copies are deleted once the model is saved',
      );
      expect(
        Directory('${store.recordDir(id).path}/inputs').existsSync(),
        isFalse,
      );
      expect(done.resultSeen, isFalse);

      final List<GenerationRecord> reloaded =
          await LibraryController.loadRecords(store);
      expect(reloaded.single.status, RecordStatus.done);
      expect(reloaded.single.name, '示例形象 9月30日');
    },
  );

  test(
    'only one generation runs at a time and unconfirmed ones need a choice',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup();
      expect(
        (await controller(container).submit(name: 'x')).block,
        SubmitBlock.incomplete,
      );

      repo.fetchGate = Completer<void>();
      await pickAll(container);
      final String first = (await controller(container).submit(name: 'a')).id!;
      await settle();
      expect(library(container).byId(first)!.status, RecordStatus.processing);

      await pickAll(container);
      expect(
        (await controller(container).submit(name: 'b')).block,
        SubmitBlock.busy,
      );

      repo.fetchGate!.complete();
      await settle();
      expect(library(container).byId(first)!.status, RecordStatus.done);

      repo.createError = const GenerationException(
        GenerationFailureKind.submissionUnknown,
      );
      final String unknown = (await controller(
        container,
      ).submit(name: 'b')).id!;
      await settle();
      expect(library(container).byId(unknown)!.status, RecordStatus.unknown);

      await pickAll(container);
      expect(
        (await controller(container).submit(name: 'c')).block,
        SubmitBlock.unconfirmed,
      );
      repo.createError = null;
      expect(
        (await controller(
          container,
        ).submit(name: 'c', allowWithUnconfirmed: true)).id,
        isNotNull,
      );
      await settle();
    },
  );

  test(
    'a lost create response is never re-sent; confirm sends it exactly once',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup();
      await pickAll(container);
      repo.createError = const GenerationException(
        GenerationFailureKind.submissionUnknown,
      );
      final String id = (await controller(container).submit(name: 'x')).id!;
      await settle();
      expect(library(container).byId(id)!.status, RecordStatus.unknown);
      expect(
        library(container).byId(id)!.inputs,
        hasLength(3),
        reason: 'photos stay locked for checking',
      );
      expect(repo.creates, 1);

      await controller(container).resumeInterrupted();
      await controller(container).continuePolling(id);
      await settle();
      expect(
        repo.creates,
        1,
        reason: 'resume and read-only actions never create',
      );

      repo.createError = null;
      final CheckOutcome outcome = await controller(
        container,
      ).confirmSubmission(id);
      await settle();
      expect(outcome, CheckOutcome.bound);
      expect(repo.creates, 2);
      expect(library(container).byId(id)!.status, RecordStatus.done);
      expect(library(container).byId(id)!.recovered, isTrue);
    },
  );

  test('a check that fails again keeps 待确认 or moves to 需人工确认', () async {
    final (:ProviderContainer container, :ScriptedRepository repo) = setup();
    await pickAll(container);
    repo.createError = const GenerationException(
      GenerationFailureKind.submissionUnknown,
    );
    final String id = (await controller(container).submit(name: 'x')).id!;
    await settle();

    expect(
      await controller(container).confirmSubmission(id),
      CheckOutcome.stillUnknown,
    );
    expect(library(container).byId(id)!.status, RecordStatus.unknown);

    repo.createError = const GenerationException(
      GenerationFailureKind.submissionUnresolved,
    );
    expect(
      await controller(container).confirmSubmission(id),
      CheckOutcome.unresolved,
    );
    expect(library(container).byId(id)!.status, RecordStatus.unresolved);
  });

  test('an inconclusive check never downgrades 需人工确认 to 待确认', () async {
    final (:ProviderContainer container, :ScriptedRepository repo) = setup();
    await pickAll(container);
    repo.createError = const GenerationException(
      GenerationFailureKind.submissionUnresolved,
    );
    final String id = (await controller(container).submit(name: 'x')).id!;
    await settle();
    expect(library(container).byId(id)!.status, RecordStatus.unresolved);

    repo.createError = const GenerationException(
      GenerationFailureKind.serviceUnavailable,
    );
    expect(
      await controller(container).confirmSubmission(id),
      CheckOutcome.unresolved,
    );
    expect(library(container).byId(id)!.status, RecordStatus.unresolved);
  });

  test(
    'restart rules: service submit → 待确认, running task → read-only resume',
    () async {
      final DateTime t = DateTime(2026, 9, 30, 12);
      final (:ProviderContainer container, :ScriptedRepository repo) = setup(
        records: <GenerationRecord>[
          GenerationRecord(
            id: 'rsubmit',
            name: 'a',
            createdAt: t,
            mode: GenerationMode.service,
            status: RecordStatus.submitting,
            inputs: const <String>['/x/f.jpg', '/x/s.jpg', '/x/b.jpg'],
          ),
          GenerationRecord(
            id: 'rcheck',
            name: 'b',
            createdAt: t,
            mode: GenerationMode.service,
            status: RecordStatus.checking,
          ),
          GenerationRecord(
            id: 'rrun',
            name: 'c',
            createdAt: t,
            mode: GenerationMode.service,
            status: RecordStatus.processing,
            taskId: 'task-9',
            origin: ModelOrigin.simulatedSample,
          ),
        ],
      );
      await controller(container).resumeInterrupted();
      await settle();
      expect(library(container).byId('rsubmit')!.status, RecordStatus.unknown);
      expect(library(container).byId('rcheck')!.status, RecordStatus.unknown);
      expect(library(container).byId('rrun')!.status, RecordStatus.done);
      expect(repo.creates, 0);
      expect(repo.fetchedTasks, <String>['task-9']);
    },
  );

  test(
    'an interrupted Mock submission restarts its local simulation',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup(
        mode: GenerationMode.mock,
        records: <GenerationRecord>[
          GenerationRecord(
            id: 'rmock',
            name: 'a',
            createdAt: DateTime(2026, 9, 30),
            mode: GenerationMode.mock,
            status: RecordStatus.submitting,
            inputs: <String>[jpeg('a').path, jpeg('b').path, jpeg('c').path],
          ),
        ],
      );
      await controller(container).resumeInterrupted();
      await settle();
      expect(repo.creates, 1);
      expect(library(container).byId('rmock')!.status, RecordStatus.done);
    },
  );

  test(
    'failures map to honest states; pre-submit ones stay out of the library',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup();
      final Map<GenerationFailureKind, RecordStatus> createCases =
          <GenerationFailureKind, RecordStatus>{
            GenerationFailureKind.serviceUnavailable: RecordStatus.offline,
            GenerationFailureKind.photosRejected: RecordStatus.rejected,
            GenerationFailureKind.serviceRejected: RecordStatus.config,
            GenerationFailureKind.submissionUnresolved: RecordStatus.unresolved,
          };
      for (final MapEntry<GenerationFailureKind, RecordStatus> entry
          in createCases.entries) {
        await pickAll(container);
        repo.createError = GenerationException(entry.key);
        final String id = (await controller(
          container,
        ).submit(name: entry.key.name, allowWithUnconfirmed: true)).id!;
        await settle();
        expect(
          library(container).byId(id)!.status,
          entry.value,
          reason: entry.key.name,
        );
        await controller(container).removeRecord(id);
      }
      repo.createError = null;

      final Map<GenerationFailureKind, RecordStatus> fetchCases =
          <GenerationFailureKind, RecordStatus>{
            GenerationFailureKind.taskFailed: RecordStatus.failed,
            GenerationFailureKind.pollingTimedOut: RecordStatus.timeout,
            GenerationFailureKind.statusUnavailable: RecordStatus.connection,
            GenerationFailureKind.downloadFailed: RecordStatus.downloadFailed,
          };
      for (final MapEntry<GenerationFailureKind, RecordStatus> entry
          in fetchCases.entries) {
        await pickAll(container);
        repo.fetchError = GenerationException(entry.key);
        final String id = (await controller(
          container,
        ).submit(name: entry.key.name)).id!;
        await settle();
        expect(
          library(container).byId(id)!.status,
          entry.value,
          reason: entry.key.name,
        );
        await controller(container).removeRecord(id);
      }

      await pickAll(container);
      repo
        ..fetchError = null
        ..createError = const GenerationException(
          GenerationFailureKind.serviceUnavailable,
        );
      final String offline = (await controller(
        container,
      ).submit(name: 'o')).id!;
      await settle();
      expect(library(container).libraryTasks, isEmpty);
      expect(library(container).hasLibraryAttention, isFalse);
      expect(library(container).byId(offline)!.info.draftLike, isTrue);
    },
  );

  test('continue polling and stop polling only read the same task', () async {
    final (:ProviderContainer container, :ScriptedRepository repo) = setup();
    await pickAll(container);
    repo.fetchError = const GenerationException(
      GenerationFailureKind.pollingTimedOut,
    );
    final String id = (await controller(container).submit(name: 'x')).id!;
    await settle();
    expect(library(container).byId(id)!.status, RecordStatus.timeout);

    repo
      ..fetchError = null
      ..fetchGate = Completer<void>();
    unawaited(controller(container).continuePolling(id));
    await settle();
    expect(library(container).byId(id)!.status, RecordStatus.processing);

    await controller(container).stopPolling(id);
    expect(library(container).byId(id)!.status, RecordStatus.paused);
    repo.fetchGate!.complete();
    await settle();
    expect(
      library(container).byId(id)!.status,
      RecordStatus.paused,
      reason: 'a stopped poll cannot overwrite the paused state',
    );

    await controller(container).continuePolling(id);
    await settle();
    expect(library(container).byId(id)!.status, RecordStatus.done);
    expect(repo.creates, 1);
  });

  test(
    'restoring a failed record puts its photos back into the draft',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup(
        mode: GenerationMode.mock,
      );
      await pickAll(container);
      repo.fetchError = const GenerationException(
        GenerationFailureKind.taskFailed,
      );
      final String id = (await controller(container).submit(name: 'x')).id!;
      await settle();
      expect(library(container).byId(id)!.status, RecordStatus.failed);
      expect(library(container).byId(id)!.inputs, hasLength(3));

      // A different draft is never replaced silently, and the record stays.
      await pickAll(container);
      final String otherDraft = container
          .read(photoFlowControllerProvider)
          .front!
          .path;
      expect(
        await controller(container).restoreToDraft(id),
        DraftRestore.draftNotEmpty,
      );
      expect(
        container.read(photoFlowControllerProvider).front!.path,
        otherDraft,
      );
      expect(library(container).byId(id), isNotNull);

      expect(
        await controller(container).restoreToDraft(id, replaceExisting: true),
        DraftRestore.restored,
      );
      final PhotoFlowState draft = container.read(photoFlowControllerProvider);
      expect(draft.isComplete, isTrue);
      expect(draft.front!.path, startsWith(store.draftDir.path));
      expect(File(otherDraft).existsSync(), isFalse);
      expect(library(container).byId(id), isNull);
      expect(store.recordDir(id).existsSync(), isFalse);
    },
  );

  test(
    'restore keeps unconfirmed records and reports photos that are gone',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup();
      await pickAll(container);
      repo.createError = const GenerationException(
        GenerationFailureKind.submissionUnknown,
      );
      final String id = (await controller(container).submit(name: 'x')).id!;
      await settle();
      expect(library(container).byId(id)!.status, RecordStatus.unknown);

      expect(
        await controller(container).restoreToDraft(id),
        DraftRestore.restored,
      );
      expect(
        library(container).byId(id)!.status,
        RecordStatus.unknown,
        reason: 'a possibly charged submission keeps its record for checking',
      );

      await container.read(photoFlowControllerProvider.notifier).reset();
      store.file(library(container).byId(id)!.inputs[1]).deleteSync();
      expect(
        await controller(container).restoreToDraft(id),
        DraftRestore.unavailable,
      );
      await settle();
      expect(container.read(photoFlowControllerProvider).isEmpty, isTrue);
      expect(
        store.draftDir.listSync().whereType<File>().map((File f) => f.path),
        everyElement(endsWith('draft.json')),
      );
    },
  );

  test(
    'a submission that cannot be stored starts nothing and keeps the draft',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup();
      await pickAll(container);
      final PhotoFlowState before = container.read(photoFlowControllerProvider);

      store.failLibraryWrites = true;
      final SubmitResult blocked = await controller(
        container,
      ).submit(name: 'x');
      await settle();
      expect(blocked.block, SubmitBlock.storage);
      expect(repo.creates, 0);
      expect(library(container).records, isEmpty);
      final PhotoFlowState after = container.read(photoFlowControllerProvider);
      expect(after.front!.path, before.front!.path);
      expect(File(after.back!.path).existsSync(), isTrue);
      expect(store.recordsDir.listSync(), isEmpty);

      store.failLibraryWrites = false;
      expect((await controller(container).submit(name: 'x')).id, isNotNull);
      await settle();
      expect(repo.creates, 1);
    },
  );

  test('a record cannot be removed while its request is in flight', () async {
    final (:ProviderContainer container, :ScriptedRepository repo) = setup();
    await pickAll(container);
    repo.createGate = Completer<void>();
    final String id = (await controller(container).submit(name: 'x')).id!;
    expect(library(container).byId(id)!.status, RecordStatus.submitting);
    expect(await controller(container).removeRecord(id), isFalse);
    expect(library(container).byId(id), isNotNull);

    repo.createGate!.complete();
    await settle();
    expect(library(container).byId(id)!.status, RecordStatus.done);
    expect(await controller(container).removeRecord(id), isTrue);
  });

  test(
    'a check waits for a running task; only a refusal proves nothing was created',
    () async {
      final (:ProviderContainer container, :ScriptedRepository repo) = setup();
      await pickAll(container);
      repo.createError = const GenerationException(
        GenerationFailureKind.submissionUnknown,
      );
      final String unknown = (await controller(
        container,
      ).submit(name: 'x')).id!;
      await settle();

      repo
        ..createError = null
        ..fetchGate = Completer<void>();
      await pickAll(container);
      await controller(container).submit(name: 'y', allowWithUnconfirmed: true);
      await settle();
      expect(
        await controller(container).confirmSubmission(unknown),
        CheckOutcome.busy,
      );
      expect(repo.creates, 2);
      repo.fetchGate!.complete();
      await settle();

      repo.createError = const GenerationException(
        GenerationFailureKind.serviceUnavailable,
      );
      expect(
        await controller(container).confirmSubmission(unknown),
        CheckOutcome.stillUnknown,
      );
      expect(library(container).byId(unknown)!.status, RecordStatus.unknown);

      repo.createError = const GenerationException(
        GenerationFailureKind.photosRejected,
      );
      expect(
        await controller(container).confirmSubmission(unknown),
        CheckOutcome.nothingCreated,
      );
      expect(library(container).byId(unknown)!.status, RecordStatus.rejected);
    },
  );

  test('records from the other mode are settled but never run', () async {
    final DateTime t = DateTime(2026, 9, 30, 12);
    final (:ProviderContainer container, :ScriptedRepository repo) = setup(
      mode: GenerationMode.mock,
      records: <GenerationRecord>[
        GenerationRecord(
          id: 'rsvcrun',
          name: 'a',
          createdAt: t,
          mode: GenerationMode.service,
          status: RecordStatus.processing,
          taskId: 'task-7',
        ),
        GenerationRecord(
          id: 'rsvcsub',
          name: 'b',
          createdAt: t,
          mode: GenerationMode.service,
          status: RecordStatus.submitting,
        ),
      ],
    );
    await controller(container).resumeInterrupted();
    await controller(container).continuePolling('rsvcrun');
    await settle();
    expect(library(container).byId('rsvcrun')!.status, RecordStatus.paused);
    expect(library(container).byId('rsvcsub')!.status, RecordStatus.unknown);
    expect(repo.fetchedTasks, isEmpty);
    expect(repo.creates, 0);

    await pickAll(container);
    expect(
      (await controller(container).submit(name: 'demo')).id,
      isNotNull,
      reason: 'a service task cannot block the local simulation',
    );
    await settle();
  });

  test(
    'damaged entries are skipped and only unreferenced record folders are swept',
    () async {
      await store.writeJson(LibraryController.fileName, <String, Object?>{
        'schemaVersion': 1,
        'records': <Object?>[
          <String, Object?>{
            'id': 'rkeep',
            'name': 'a',
            'createdAt': '2026-09-30T12:00:00.000',
            'mode': 'mock',
            'status': 'done',
            'taskId': 42,
            'modelBytes': 'big',
          },
          'not a record',
          <String, Object?>{'id': 'rbroken'},
        ],
      });
      final List<GenerationRecord> loaded = await LibraryController.loadRecords(
        store,
      );
      expect(loaded.map((GenerationRecord r) => r.id), <String>['rkeep']);
      expect(loaded.single.taskId, isNull);
      expect(loaded.single.modelBytes, isNull);

      store.recordDir('rkeep').createSync(recursive: true);
      store.recordDir('rorphan').createSync(recursive: true);
      expect(await LibraryController.indexIntact(store), isTrue);
      await LibraryController.sweepOrphans(store, loaded);
      expect(store.recordDir('rkeep').existsSync(), isTrue);
      expect(store.recordDir('rorphan').existsSync(), isFalse);

      store.file(LibraryController.fileName).writeAsStringSync('{broken');
      expect(await LibraryController.indexIntact(store), isFalse);
    },
  );

  test('removing a record during a run ignores its late result', () async {
    final (:ProviderContainer container, :ScriptedRepository repo) = setup();
    await pickAll(container);
    repo.fetchGate = Completer<void>();
    final String id = (await controller(container).submit(name: 'x')).id!;
    await settle();
    await controller(container).removeRecord(id);
    repo.fetchGate!.complete();
    await settle();
    expect(library(container).records, isEmpty);
    expect((await LibraryController.loadRecords(store)), isEmpty);
  });

  test(
    'a missing model file is detected and re-downloaded without generating',
    () async {
      final File glb = File('${temp.path}/remote.glb')
        ..writeAsBytesSync(<int>[
          ...'glTF'.codeUnits,
          2,
          0,
          0,
          0,
          20,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
      final (:ProviderContainer container, :ScriptedRepository repo) = setup(
        records: <GenerationRecord>[
          GenerationRecord(
            id: 'rgone',
            name: 'a',
            createdAt: DateTime(2026, 9, 29),
            mode: GenerationMode.service,
            status: RecordStatus.done,
            taskId: 'task-1',
            origin: ModelOrigin.serviceGenerated,
            model: const ModelRef.file('records/rgone/model.glb'),
          ),
        ],
      );
      repo.modelSrc = Uri.file(glb.path).toString();
      await controller(container).resumeInterrupted();
      expect(library(container).missingFiles, contains('rgone'));

      expect(
        await controller(container).redownload('rgone'),
        RedownloadOutcome.restored,
      );
      expect(library(container).missingFiles, isNot(contains('rgone')));
      expect(store.file('records/rgone/model.glb').existsSync(), isTrue);
      expect(repo.creates, 0);

      // Next launch (records read from disk): the file is gone again and the service no
      // longer has the task (S15b).
      await controller(container).rename('rgone', 'b');
      store.file('records/rgone/model.glb').deleteSync();
      final (
        container: ProviderContainer relaunched,
        repo: ScriptedRepository again,
      ) = setup(
        records: await LibraryController.loadRecords(store),
      );
      again.fetchError = const GenerationException(
        GenerationFailureKind.taskFailed,
      );
      await controller(relaunched).resumeInterrupted();
      expect(library(relaunched).missingFiles, contains('rgone'));
      expect(
        await controller(relaunched).redownload('rgone'),
        RedownloadOutcome.expired,
      );
      expect(library(relaunched).expiredFiles, contains('rgone'));
    },
  );

  test('a rebuilt controller keeps the latest records', () async {
    final (:ProviderContainer container, repo: _) = setup(
      mode: GenerationMode.mock,
    );
    await pickAll(container);
    final String id = (await controller(container).submit(name: 'x')).id!;
    await settle();
    container.invalidate(libraryControllerProvider);
    expect(library(container).byId(id)!.status, RecordStatus.done);
  });

  test(
    'clear all removes records, drafts and files but keeps onboarding done',
    () async {
      final (:ProviderContainer container, repo: _) = setup(
        mode: GenerationMode.mock,
      );
      await pickAll(container);
      await controller(container).submit(name: 'x');
      await settle();
      await pickAll(container);

      await controller(container).clearAll();
      expect(library(container).records, isEmpty);
      expect(container.read(photoFlowControllerProvider).isEmpty, isTrue);
      expect(container.read(appSettingsProvider).onboardingDone, isTrue);
      expect(store.recordsDir.listSync(), isEmpty);
      expect(await LibraryController.loadRecords(store), isEmpty);
    },
  );

  test(
    'draft photos persist, are validated, and leave picker cache copies behind',
    () async {
      final Directory cache = Directory('${temp.path}/cache/picker')
        ..createSync(recursive: true);
      final File picked = File('${cache.path}/IMG.jpg')
        ..writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xE1, 0, 0, 0, 0]);
      final File heic = File('${temp.path}/IMG.heic')
        ..writeAsBytesSync(<int>[
          0,
          0,
          0,
          24,
          ...'ftypheic'.codeUnits,
          0,
          0,
          0,
          0,
        ]);
      bool strict = false;
      final FileDraftPhotoStore drafts = FileDraftPhotoStore(
        store,
        strictFormats: () => strict,
        cacheRoot: '${temp.path}/cache',
      );

      final XFile front = await drafts.adopt(
        PhotoAngle.front,
        XFile(picked.path),
      );
      expect(front.path, startsWith(store.draftDir.path));
      expect(
        picked.existsSync(),
        isFalse,
        reason: 'the picker cache copy is purged',
      );
      expect(
        (await drafts.adopt(PhotoAngle.side, XFile(heic.path))).path,
        endsWith('.heic'),
      );
      expect(
        heic.existsSync(),
        isTrue,
        reason: 'files outside the cache are never deleted',
      );

      strict = true;
      await expectLater(
        drafts.adopt(PhotoAngle.back, XFile(heic.path)),
        throwsA(isA<PhotoRejected>()),
      );
      final File text = File('${temp.path}/notes.txt')
        ..writeAsStringSync('hello');
      strict = false;
      await expectLater(
        drafts.adopt(PhotoAngle.back, XFile(text.path)),
        throwsA(isA<PhotoRejected>()),
      );

      await drafts.persist(PhotoFlowState(front: front));
      final Map<PhotoAngle, XFile> loaded = await drafts.load();
      expect(loaded.keys, <PhotoAngle>[PhotoAngle.front]);
      expect(loaded[PhotoAngle.front]!.path, front.path);
    },
  );
}

/// Real file store whose index writes can be made to fail (e.g. a full disk).
class FlakyStore extends LocalStore {
  FlakyStore({required super.root, required super.exportsDir});

  bool failLibraryWrites = false;

  @override
  Future<void> writeJson(String name, Map<String, Object?> json) {
    if (failLibraryWrites && name == LibraryController.fileName) {
      return Future<void>.error(const FileSystemException('No space left'));
    }
    return super.writeJson(name, json);
  }
}

class ScriptedRepository implements DigitalTwinRepository {
  int creates = 0;
  Completer<void>? createGate;
  final List<String> fetchedTasks = <String>[];
  GenerationException? createError;
  GenerationException? fetchError;
  Completer<void>? fetchGate;
  String modelSrc = sampleModelAsset;

  @override
  Future<GenerationTask> createTask({
    required XFile front,
    required XFile side,
    required XFile back,
  }) async {
    creates++;
    final Completer<void>? gate = createGate;
    if (gate != null) {
      await gate.future;
    }
    final GenerationException? error = createError;
    if (error != null) {
      throw error;
    }
    return GenerationTask(
      id: 'task-$creates',
      origin: ModelOrigin.simulatedSample,
    );
  }

  @override
  Future<DigitalTwinModel> fetchModel(
    GenerationTask task, {
    ValueChanged<int>? onProgress,
  }) async {
    fetchedTasks.add(task.id);
    onProgress?.call(40);
    final Completer<void>? gate = fetchGate;
    if (gate != null) {
      await gate.future;
    }
    final GenerationException? error = fetchError;
    if (error != null) {
      throw error;
    }
    return DigitalTwinModel(src: modelSrc, origin: task.origin);
  }
}

class FakePicker extends ImagePicker {
  FakePicker(List<XFile> files) : _files = files;

  final List<XFile> _files;
  final Queue<int> _order = Queue<int>();
  int _next = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    _order.add(_next);
    final XFile original = _files[_next++ % _files.length];
    // Each pick returns a fresh copy (the draft adopts and may move it).
    final File copy = File('${original.path}.$_next.jpg');
    File(original.path).copySync(copy.path);
    return XFile(copy.path);
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse.empty();
}
