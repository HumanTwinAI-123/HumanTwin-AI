import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/primary_button.dart';
import 'photo_flow_controller.dart';

class PhotoConfirmationScreen extends ConsumerWidget {
  const PhotoConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PhotoFlowState state = ref.watch(photoFlowControllerProvider);

    if (!state.isComplete) {
      return const _IncompleteConfirmationView();
    }

    return Scaffold(
      body: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _ConfirmationGridPainter()),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey<String>(
                            'photo-confirmation-scroll',
                          ),
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const _ConfirmationHeader(),
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
                                child: _ConfirmationIntro(),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                ),
                                child: Column(
                                  children: <Widget>[
                                    _ConfirmationPhotoCard(
                                      angle: PhotoAngle.front,
                                      label: '正面照片',
                                      englishLabel: 'FRONT',
                                      image: state.front!,
                                    ),
                                    const SizedBox(height: 8),
                                    _ConfirmationPhotoCard(
                                      angle: PhotoAngle.side,
                                      label: '侧面照片',
                                      englishLabel: 'SIDE',
                                      image: state.side!,
                                    ),
                                    const SizedBox(height: 8),
                                    _ConfirmationPhotoCard(
                                      angle: PhotoAngle.back,
                                      label: '背面照片',
                                      englishLabel: 'BACK',
                                      image: state.back!,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 74),
                                child: _ConfirmationStepIndicator(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: PrimaryButton(
                          key: const ValueKey<String>('photo-confirmation-cta'),
                          label: '开始生成',
                          width: double.infinity,
                          onPressed: () => context.push('/processing'),
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
}

class _ConfirmationHeader extends StatelessWidget {
  const _ConfirmationHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('photo-confirmation-back'),
              tooltip: '返回',
              onPressed: () => _returnToSelection(context),
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
            Text('照片确认', style: Theme.of(context).textTheme.titleLarge),
            if (MediaQuery.textScalerOf(context).scale(1) < 1.3) ...<Widget>[
              const Spacer(),
              Text(
                '04 / 06',
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

class _ConfirmationIntro extends StatelessWidget {
  const _ConfirmationIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('确认三视图照片', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(
          '请确认照片方向和内容无误，\n如需调整，可点按对应照片返回修改。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _ConfirmationPhotoCard extends StatelessWidget {
  const _ConfirmationPhotoCard({
    required this.angle,
    required this.label,
    required this.englishLabel,
    required this.image,
  });

  final PhotoAngle angle;
  final String label;
  final String englishLabel;
  final XFile image;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$label，$englishLabel，已添加，可返回修改',
      child: Container(
        key: ValueKey<String>('photo-confirmation-card-${angle.name}'),
        constraints: const BoxConstraints(minHeight: 154),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _ConfirmationPhotoPreview(angle: angle, label: label, image: image),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$englishLabel\n已添加 · 修改',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 15 / 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              button: true,
              label: '修改$label',
              child: IconButton(
                key: ValueKey<String>('photo-confirmation-edit-${angle.name}'),
                tooltip: '修改$label',
                onPressed: () => _returnToSelection(context),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.background,
                  minimumSize: const Size.square(38),
                  maximumSize: const Size.square(38),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                icon: const Text(
                  '改',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 11,
                    height: 16 / 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmationPhotoPreview extends StatefulWidget {
  const _ConfirmationPhotoPreview({
    required this.angle,
    required this.label,
    required this.image,
  });

  final PhotoAngle angle;
  final String label;
  final XFile image;

  @override
  State<_ConfirmationPhotoPreview> createState() =>
      _ConfirmationPhotoPreviewState();
}

class _ConfirmationPhotoPreviewState extends State<_ConfirmationPhotoPreview> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.image.readAsBytes();
  }

  @override
  void didUpdateWidget(covariant _ConfirmationPhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) {
      _bytes = widget.image.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 102,
      height: 126,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.requireData,
              key: ValueKey<String>(
                'photo-confirmation-image-${widget.angle.name}-${widget.image.path}',
              ),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              cacheWidth: 512,
              semanticLabel: '${widget.label}照片',
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const _ConfirmationImageFallback();
                  },
            );
          }
          if (snapshot.hasError) {
            return const _ConfirmationImageFallback();
          }
          return const Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                color: AppColors.textTertiary,
                strokeWidth: 1.5,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConfirmationImageFallback extends StatelessWidget {
  const _ConfirmationImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.textTertiary,
        size: 32,
      ),
    );
  }
}

class _ConfirmationStepIndicator extends StatelessWidget {
  const _ConfirmationStepIndicator();

  static const List<(String, String)> _steps = <(String, String)>[
    ('首页', '已完成'),
    ('说明', '已完成'),
    ('照片', '当前'),
    ('生成', '稍后'),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '当前步骤：照片确认，第 3 步',
      child: SizedBox(
        height: 96,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _ConfirmationStepTrackPainter()),
            ),
            Row(
              children: <Widget>[
                for (int index = 0; index < _steps.length; index++)
                  Expanded(
                    child: _ConfirmationStepItem(
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

class _ConfirmationStepItem extends StatelessWidget {
  const _ConfirmationStepItem({
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

class _ConfirmationStepTrackPainter extends CustomPainter {
  const _ConfirmationStepTrackPainter();

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

class _ConfirmationGridPainter extends CustomPainter {
  const _ConfirmationGridPainter();

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

class _IncompleteConfirmationView extends StatelessWidget {
  const _IncompleteConfirmationView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 16),
                  const _ConfirmationHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.page),
                      child: Container(
                        key: const ValueKey<String>(
                          'photo-confirmation-incomplete',
                        ),
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          border: Border.all(color: AppColors.borderSubtle),
                          borderRadius: BorderRadius.circular(AppRadii.medium),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '照片尚未完整',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '请返回照片选择，补齐正面、侧面和背面照片后再开始生成。',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: PrimaryButton(
                      key: const ValueKey<String>(
                        'photo-confirmation-incomplete-action',
                      ),
                      label: '返回照片选择',
                      width: double.infinity,
                      onPressed: () => context.go('/photos'),
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

void _returnToSelection(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/photos');
  }
}
