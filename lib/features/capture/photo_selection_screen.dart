import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/photo_slot.dart';
import '../../shared/widgets/primary_button.dart';
import 'photo_flow_controller.dart';

class PhotoSelectionScreen extends ConsumerStatefulWidget {
  const PhotoSelectionScreen({super.key});

  @override
  ConsumerState<PhotoSelectionScreen> createState() =>
      _PhotoSelectionScreenState();
}

class _PhotoSelectionScreenState extends ConsumerState<PhotoSelectionScreen>
    with WidgetsBindingObserver {
  bool _isRecoveringLostData = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_retrieveLostData());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_retrieveLostData());
    }
  }

  Future<void> _retrieveLostData() async {
    if (_isRecoveringLostData) {
      return;
    }
    _isRecoveringLostData = true;
    try {
      await ref.read(photoFlowControllerProvider.notifier).retrieveLostData();
    } finally {
      _isRecoveringLostData = false;
    }
  }

  Future<void> _showPhotoActions(
    PhotoAngle angle, {
    required bool hasPhoto,
  }) async {
    final _PhotoAction? action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface1,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.large),
        ),
      ),
      builder: (BuildContext context) =>
          _PhotoActionSheet(angle: angle, hasPhoto: hasPhoto),
    );

    if (!mounted || action == null || action == _PhotoAction.cancel) {
      return;
    }

    final PhotoFlowController controller = ref.read(
      photoFlowControllerProvider.notifier,
    );
    switch (action) {
      case _PhotoAction.camera:
        await _pick(
          controller,
          angle,
          source: ImageSource.camera,
          isReplace: hasPhoto,
        );
      case _PhotoAction.gallery:
        await _pick(
          controller,
          angle,
          source: ImageSource.gallery,
          isReplace: hasPhoto,
        );
      case _PhotoAction.remove:
        controller.remove(angle);
      case _PhotoAction.cancel:
        break;
    }
  }

  Future<void> _pick(
    PhotoFlowController controller,
    PhotoAngle angle, {
    required ImageSource source,
    required bool isReplace,
  }) async {
    if (isReplace) {
      await controller.replace(angle, source: source);
    } else {
      await controller.select(angle, source: source);
    }
    if (!mounted) {
      return;
    }
    final String? error = ref.read(photoFlowControllerProvider).errorFor(angle);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final PhotoFlowState state = ref.watch(photoFlowControllerProvider);

    return Scaffold(
      body: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _SelectionGridPainter()),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey<String>('photo-selection-scroll'),
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const _SelectionHeader(),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page,
                                ),
                                child: Divider(
                                  height: 29,
                                  thickness: 1,
                                  color: AppColors.borderSubtle.withValues(
                                    alpha: 0.68,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page,
                                ),
                                child: _SelectionIntro(),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                ),
                                child: Column(
                                  children: <Widget>[
                                    _buildPhotoSlot(
                                      state,
                                      angle: PhotoAngle.front,
                                      label: '正面照片',
                                      englishLabel: 'FRONT',
                                      placeholderAsset:
                                          'assets/images/photo_guide_scan_suit_front.png',
                                    ),
                                    const SizedBox(height: 8),
                                    _buildPhotoSlot(
                                      state,
                                      angle: PhotoAngle.side,
                                      label: '侧面照片',
                                      englishLabel: 'SIDE',
                                      placeholderAsset:
                                          'assets/images/photo_guide_scan_suit_side.png',
                                    ),
                                    const SizedBox(height: 8),
                                    _buildPhotoSlot(
                                      state,
                                      angle: PhotoAngle.back,
                                      label: '背面照片',
                                      englishLabel: 'BACK',
                                      placeholderAsset:
                                          'assets/images/photo_guide_scan_suit_back.png',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 74),
                                child: _SelectionStepIndicator(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: PrimaryButton(
                          key: const ValueKey<String>('photo-selection-cta'),
                          label: '下一步',
                          width: double.infinity,
                          onPressed: state.isComplete
                              ? () => context.push('/photo-confirmation')
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSlot(
    PhotoFlowState state, {
    required PhotoAngle angle,
    required String label,
    required String englishLabel,
    required String placeholderAsset,
  }) {
    final XFile? photo = state.photoFor(angle);
    final String? error = state.errorFor(angle);
    final PhotoSlotState slotState = photo != null
        ? PhotoSlotState.filled
        : error != null
        ? PhotoSlotState.error
        : PhotoSlotState.empty;

    return PhotoSlot(
      key: ValueKey<String>('photo-slot-${angle.name}'),
      label: label,
      englishLabel: englishLabel,
      image: photo,
      state: slotState,
      placeholderAsset: placeholderAsset,
      onPick: () => unawaited(_showPhotoActions(angle, hasPhoto: false)),
      onReplace: () => unawaited(_showPhotoActions(angle, hasPhoto: true)),
      onRemove: () =>
          ref.read(photoFlowControllerProvider.notifier).remove(angle),
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('photo-selection-back'),
              tooltip: '返回',
              onPressed: context.pop,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface1,
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderSubtle),
                minimumSize: const Size.square(44),
                maximumSize: const Size.square(44),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Text('照片选择', style: Theme.of(context).textTheme.titleLarge),
            if (MediaQuery.textScalerOf(context).scale(1) < 1.3) ...<Widget>[
              const Spacer(),
              Text(
                '03 / 06',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: AppColors.textTertiary.withValues(alpha: 0.82),
                  fontFamily: 'monospace',
                  fontSize: 9,
                  height: 12 / 9,
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectionIntro extends StatelessWidget {
  const _SelectionIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('选择三视图照片', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(
          '请添加正面、侧面和背面全身照片，\n确保身体完整入镜并符合拍摄要求。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

enum _PhotoAction { camera, gallery, remove, cancel }

class _PhotoActionSheet extends StatelessWidget {
  const _PhotoActionSheet({required this.angle, required this.hasPhoto});

  final PhotoAngle angle;
  final bool hasPhoto;

  String get _label => switch (angle) {
    PhotoAngle.front => '正面',
    PhotoAngle.side => '侧面',
    PhotoAngle.back => '背面',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                hasPhoto ? '管理$_label照片' : '添加$_label照片',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const ValueKey<String>('photo-action-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(hasPhoto ? '拍摄新照片' : '拍摄照片'),
              subtitle: const Text('使用相机拍摄全身照片'),
              onTap: () => Navigator.pop(context, _PhotoAction.camera),
            ),
            ListTile(
              key: const ValueKey<String>('photo-action-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              subtitle: const Text('选择设备中的已有照片'),
              onTap: () => Navigator.pop(context, _PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                key: const ValueKey<String>('photo-action-remove'),
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: const Text(
                  '删除照片',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
            ListTile(
              key: const ValueKey<String>('photo-action-cancel'),
              leading: const Icon(Icons.close_rounded),
              title: const Text('取消'),
              onTap: () => Navigator.pop(context, _PhotoAction.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionStepIndicator extends StatelessWidget {
  const _SelectionStepIndicator();

  static const List<(String, String)> _steps = <(String, String)>[
    ('首页', '已完成'),
    ('说明', '已完成'),
    ('照片', '当前'),
    ('生成', '稍后'),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '当前步骤：照片选择，第 3 步',
      child: SizedBox(
        height: 96,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _SelectionStepTrackPainter()),
            ),
            Row(
              children: <Widget>[
                for (int index = 0; index < _steps.length; index++)
                  Expanded(
                    child: _SelectionStepItem(
                      number: index + 1,
                      label: _steps[index].$1,
                      state: _steps[index].$2,
                      isReached: index <= 2,
                      isCurrent: index == 2,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionStepItem extends StatelessWidget {
  const _SelectionStepItem({
    required this.number,
    required this.label,
    required this.state,
    required this.isReached,
    required this.isCurrent,
  });

  final int number;
  final String label;
  final String state;
  final bool isReached;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = isCurrent
        ? AppColors.accentPrimary
        : AppColors.textSecondary.withValues(alpha: isReached ? 0.58 : 0.44);
    final Color circleColor = isCurrent
        ? AppColors.accentPrimary
        : isReached
        ? AppColors.accentPrimary.withValues(alpha: 0.52)
        : Colors.transparent;
    final Color numberColor = isCurrent
        ? AppColors.background
        : isReached
        ? AppColors.background.withValues(alpha: 0.72)
        : AppColors.textSecondary.withValues(alpha: 0.44);

    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Column(
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              border: isReached
                  ? null
                  : Border.all(
                      color: AppColors.borderSubtle.withValues(alpha: 0.44),
                    ),
            ),
            child: Text(
              '$number',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: numberColor,
                fontFamily: 'monospace',
                fontSize: 7,
                height: 10 / 7,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: labelColor,
              fontSize: 8,
              height: 11 / 8,
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            state,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(
                alpha: isCurrent ? 0.56 : (isReached ? 0.38 : 0.26),
              ),
              fontFamily: 'monospace',
              fontSize: 6,
              height: 8 / 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionStepTrackPainter extends CustomPainter {
  const _SelectionStepTrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double start = size.width / 8;
    final double current = size.width * 5 / 8;
    final double end = size.width * 7 / 8;
    const double y = 23;
    canvas.drawLine(
      Offset(start, y),
      Offset(end, y),
      Paint()
        ..color = AppColors.borderSubtle.withValues(alpha: 0.44)
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      Offset(start, y),
      Offset(current, y),
      Paint()
        ..color = AppColors.accentPrimary.withValues(alpha: 0.52)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SelectionGridPainter extends CustomPainter {
  const _SelectionGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double x = 65; x < size.width; x += 65) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 84; y < size.height; y += 84) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PhotoConfirmationPlaceholderScreen extends StatelessWidget {
  const PhotoConfirmationPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: IconButton(
                    tooltip: '返回',
                    onPressed: context.pop,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '照片确认',
                        key: const ValueKey<String>(
                          'photo-confirmation-placeholder',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'DAY 5 · PLACEHOLDER',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          height: 1.4,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
