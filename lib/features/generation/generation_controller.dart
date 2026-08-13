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

  Future<void> _generate() async {
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
      state = const GenerationState(status: GenerationStatus.success);
    } on Object {
      state = const GenerationState(
        status: GenerationStatus.failure,
        errorMessage: '生成过程中出现问题，请重新尝试',
      );
    }
  }
}
