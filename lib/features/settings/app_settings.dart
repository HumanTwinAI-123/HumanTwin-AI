import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/storage/local_store.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.onboardingDone = false,
    this.showGuide = true,
    this.deleteInputCopies = true,
  });

  static const String fileName = 'settings.json';
  static const int schemaVersion = 1;

  /// The one-time welcome page has been completed.
  final bool onboardingDone;

  /// Show 拍摄说明 before photo selection.
  final bool showGuide;

  /// Delete a record's photo copies once its model is saved (D3 default: on).
  final bool deleteInputCopies;

  AppSettings copyWith({
    bool? onboardingDone,
    bool? showGuide,
    bool? deleteInputCopies,
  }) {
    return AppSettings(
      onboardingDone: onboardingDone ?? this.onboardingDone,
      showGuide: showGuide ?? this.showGuide,
      deleteInputCopies: deleteInputCopies ?? this.deleteInputCopies,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'onboardingDone': onboardingDone,
    'showGuide': showGuide,
    'deleteInputCopies': deleteInputCopies,
  };

  static AppSettings fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return const AppSettings();
    }
    return AppSettings(
      onboardingDone: json['onboardingDone'] == true,
      showGuide: json['showGuide'] != false,
      deleteInputCopies: json['deleteInputCopies'] != false,
    );
  }

  static Future<AppSettings> load(LocalStore store) async =>
      fromJson(await store.readJson(fileName));
}

/// Settings read before the first frame (overridden at startup).
final initialSettingsProvider = Provider<AppSettings>(
  (Ref ref) => const AppSettings(),
);

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends Notifier<AppSettings> {
  Future<void> _writes = Future<void>.value();

  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    state = change(state);
    await _persist();
  }

  Future<void> completeOnboarding() =>
      update((AppSettings s) => s.copyWith(onboardingDone: true));

  Future<void> setShowGuide(bool value) =>
      update((AppSettings s) => s.copyWith(showGuide: value));

  Future<void> setDeleteInputCopies(bool value) =>
      update((AppSettings s) => s.copyWith(deleteInputCopies: value));

  /// After 「清除全部本机数据」: defaults, but the welcome page is not shown again.
  Future<void> resetKeepingOnboarding() =>
      update((AppSettings s) => const AppSettings(onboardingDone: true));

  /// Serialised writes: the last change always lands last.
  Future<void> _persist() {
    final Map<String, Object?> json = state.toJson();
    final LocalStore store = ref.read(localStoreProvider);
    return _writes = _writes.then((_) async {
      try {
        await store.writeJson(AppSettings.fileName, json);
      } on Object catch (error) {
        // Settings stay in memory; the next change retries the write.
        debugPrint('Settings could not be saved: $error');
      }
    });
  }
}
