import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoAngle { front, side, back }

@immutable
class PhotoFlowState {
  const PhotoFlowState({
    this.front,
    this.side,
    this.back,
    this.pendingAngle,
    this.errorAngle,
    this.errorMessage,
  });

  static const Object _notProvided = Object();

  final XFile? front;
  final XFile? side;
  final XFile? back;
  final PhotoAngle? pendingAngle;
  final PhotoAngle? errorAngle;
  final String? errorMessage;

  bool get isComplete => front != null && side != null && back != null;

  bool get isPicking => pendingAngle != null;

  XFile? photoFor(PhotoAngle angle) {
    return switch (angle) {
      PhotoAngle.front => front,
      PhotoAngle.side => side,
      PhotoAngle.back => back,
    };
  }

  String? errorFor(PhotoAngle angle) {
    return errorAngle == angle ? errorMessage : null;
  }

  PhotoFlowState copyWith({
    Object? front = _notProvided,
    Object? side = _notProvided,
    Object? back = _notProvided,
    Object? pendingAngle = _notProvided,
    Object? errorAngle = _notProvided,
    Object? errorMessage = _notProvided,
  }) {
    return PhotoFlowState(
      front: identical(front, _notProvided) ? this.front : front as XFile?,
      side: identical(side, _notProvided) ? this.side : side as XFile?,
      back: identical(back, _notProvided) ? this.back : back as XFile?,
      pendingAngle: identical(pendingAngle, _notProvided)
          ? this.pendingAngle
          : pendingAngle as PhotoAngle?,
      errorAngle: identical(errorAngle, _notProvided)
          ? this.errorAngle
          : errorAngle as PhotoAngle?,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

final imagePickerProvider = Provider<ImagePicker>((Ref ref) => ImagePicker());

final lostDataRecoverySupportedProvider = Provider<bool>(
  (Ref ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

final photoFlowControllerProvider =
    NotifierProvider<PhotoFlowController, PhotoFlowState>(
      PhotoFlowController.new,
    );

class PhotoFlowController extends Notifier<PhotoFlowState> {
  late ImagePicker _picker;
  var _operationGeneration = 0;
  Future<void>? _lostDataRecovery;

  @override
  PhotoFlowState build() {
    _picker = ref.watch(imagePickerProvider);
    return const PhotoFlowState();
  }

  bool get isComplete => state.isComplete;

  Future<void> select(PhotoAngle angle, {required ImageSource source}) async {
    if (state.isPicking) {
      return;
    }

    final PhotoFlowState beforePick = state;
    final int operation = ++_operationGeneration;
    state = state.copyWith(
      pendingAngle: angle,
      errorAngle: null,
      errorMessage: null,
    );

    try {
      final XFile? photo = await _picker.pickImage(source: source);
      if (operation != _operationGeneration) {
        return;
      }
      if (photo == null) {
        state = beforePick;
        return;
      }
      state = _withPhoto(
        beforePick,
        angle,
        photo,
      ).copyWith(pendingAngle: null, errorAngle: null, errorMessage: null);
    } on Object {
      if (operation != _operationGeneration) {
        return;
      }
      state = beforePick.copyWith(
        pendingAngle: null,
        errorAngle: angle,
        errorMessage: '照片选择失败，请重试',
      );
    }
  }

  Future<void> replace(PhotoAngle angle, {required ImageSource source}) {
    return select(angle, source: source);
  }

  void remove(PhotoAngle angle) {
    _operationGeneration++;
    state = _withPhoto(state, angle, null).copyWith(
      pendingAngle: null,
      errorAngle: state.errorAngle == angle ? null : state.errorAngle,
      errorMessage: state.errorAngle == angle ? null : state.errorMessage,
    );
  }

  void reset() {
    _operationGeneration++;
    state = const PhotoFlowState();
  }

  Future<void> retrieveLostData() async {
    final Future<void>? activeRecovery = _lostDataRecovery;
    if (activeRecovery != null) {
      await activeRecovery;
      return;
    }

    final Future<void> recovery = _retrieveLostDataOnce();
    _lostDataRecovery = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_lostDataRecovery, recovery)) {
        _lostDataRecovery = null;
      }
    }
  }

  Future<void> _retrieveLostDataOnce() async {
    if (!ref.read(lostDataRecoverySupportedProvider)) {
      return;
    }

    final int operationAtStart = _operationGeneration;
    final PhotoFlowState stateAtStart = state;
    final PhotoAngle? target =
        stateAtStart.pendingAngle ?? _firstEmptyAngle(stateAtStart);

    final LostDataResponse response;
    try {
      response = await _picker.retrieveLostData();
    } on Object {
      return;
    }

    if (response.isEmpty) {
      return;
    }

    if (operationAtStart != _operationGeneration ||
        !identical(state, stateAtStart) ||
        target == null) {
      return;
    }

    final XFile? recovered = response.file ?? response.files?.firstOrNull;
    if (recovered != null && response.type != RetrieveType.video) {
      _operationGeneration++;
      state = _withPhoto(
        stateAtStart,
        target,
        recovered,
      ).copyWith(pendingAngle: null, errorAngle: null, errorMessage: null);
      return;
    }

    if (response.exception != null) {
      _operationGeneration++;
      state = stateAtStart.copyWith(
        pendingAngle: null,
        errorAngle: target,
        errorMessage: '照片恢复失败，请重新选择',
      );
    }
  }

  PhotoAngle? _firstEmptyAngle(PhotoFlowState current) {
    for (final PhotoAngle angle in PhotoAngle.values) {
      if (current.photoFor(angle) == null) {
        return angle;
      }
    }
    return null;
  }

  PhotoFlowState _withPhoto(
    PhotoFlowState current,
    PhotoAngle angle,
    XFile? photo,
  ) {
    return switch (angle) {
      PhotoAngle.front => current.copyWith(front: photo),
      PhotoAngle.side => current.copyWith(side: photo),
      PhotoAngle.back => current.copyWith(back: photo),
    };
  }
}
