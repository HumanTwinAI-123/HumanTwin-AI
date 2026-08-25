import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../capture/photo_flow_controller.dart';
import 'digital_twin_repository.dart';

enum GenerationStatus { idle, processing, success, failure }

@immutable
class GenerationState {
  const GenerationState({
    this.status = GenerationStatus.idle,
    this.errorMessage,
  });

  final GenerationStatus status;
  final String? errorMessage;
}

final generationControllerProvider =
    NotifierProvider<GenerationController, GenerationState>(
      GenerationController.new,
    );

class GenerationController extends Notifier<GenerationState> {
  var _runGeneration = 0;

  @override
  GenerationState build() => const GenerationState();

  Future<void> start() async {
    if (state.status != GenerationStatus.idle) {
      return;
    }
    await _generate();
  }

  Future<void> retry() async {
    if (state.status != GenerationStatus.failure) {
      return;
    }
    await _generate();
  }

  /// Clears any previous result and starts a fresh generation run.
  ///
  /// Called once per fresh [ProcessingScreen] mount so every new entry replays
  /// the processing animation instead of reusing a cached success/failure.
  Future<void> restart() async {
    state = const GenerationState();
    await _generate();
  }

  Future<void> _generate() async {
    final int run = ++_runGeneration;
    final PhotoFlowState photos = ref.read(photoFlowControllerProvider);
    final XFile? front = photos.front;
    final XFile? side = photos.side;
    final XFile? back = photos.back;

    if (front == null || side == null || back == null) {
      state = const GenerationState(
        status: GenerationStatus.failure,
        errorMessage: '照片尚未完整',
      );
      return;
    }

    state = const GenerationState(status: GenerationStatus.processing);
    try {
      await ref
          .read(digitalTwinRepositoryProvider)
          .generateDigitalTwin(front: front, side: side, back: back);
      // Ignore a stale run that finished after a newer run superseded it.
      if (run != _runGeneration) {
        return;
      }
      state = const GenerationState(status: GenerationStatus.success);
    } on Object {
      if (run != _runGeneration) {
        return;
      }
      state = const GenerationState(
        status: GenerationStatus.failure,
        errorMessage: '生成过程中出现问题，请重新尝试',
      );
    }
  }
}
