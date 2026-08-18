import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/primary_button.dart';
import '../capture/photo_flow_controller.dart';
import 'generation_controller.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(photoFlowControllerProvider).isComplete) {
        unawaited(ref.read(generationControllerProvider.notifier).start());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final PhotoFlowState photos = ref.watch(photoFlowControllerProvider);
    if (!photos.isComplete) {
      return const _IncompleteProcessingView();
    }

    final GenerationState generation = ref.watch(generationControllerProvider);
    return Scaffold(
      key: const ValueKey<String>('processing-screen'),
      body: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _ProcessingGridPainter()),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          return SingleChildScrollView(
                            key: const ValueKey<String>('processing-scroll'),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: math.max(
                                  0,
                                  constraints.maxHeight - 36,
                                ),
                              ),
                              child: _ProcessingContent(generation: generation),
                            ),
                          );
                        },
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

class _ProcessingContent extends ConsumerWidget {
  const _ProcessingContent({required this.generation});

  final GenerationState generation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _ProcessingCopy copy = _ProcessingCopy.forState(generation);
    final bool showStepCount = MediaQuery.textScalerOf(context).scale(9) <= 13;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('processing-back'),
              tooltip: '返回',
              onPressed: () => _returnFromProcessing(context),
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
            Expanded(
              child: Text(
                copy.header,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (showStepCount)
              Text(
                '05 / 06',
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
        ),
        Divider(
          height: 29,
          thickness: 1,
          color: AppColors.borderSubtle.withValues(alpha: 0.68),
        ),
        Text(copy.headline, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(copy.supporting, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.page),
        _DigitalHumanVisual(status: generation.status),
        const SizedBox(height: AppSpacing.lg),
        Align(
          child: _StatusPill(
            status: generation.status,
            label: copy.statusLabel,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          copy.footer,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (generation.status == GenerationStatus.success) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            key: const ValueKey<String>('processing-view-twin-cta'),
            label: '查看数字人体',
            width: double.infinity,
            onPressed: () => context.push('/viewer'),
          ),
        ],
        if (generation.status == GenerationStatus.failure) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            key: const ValueKey<String>('processing-retry-cta'),
            label: '重试',
            width: double.infinity,
            onPressed: () => unawaited(
              ref.read(generationControllerProvider.notifier).retry(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const ValueKey<String>('processing-return-cta'),
              onPressed: () => _returnFromProcessing(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.borderSubtle),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
              ),
              child: const Text('返回'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _ProcessingStepIndicator(),
      ],
    );
  }
}

class _DigitalHumanVisual extends StatelessWidget {
  const _DigitalHumanVisual({required this.status});

  final GenerationStatus status;

  @override
  Widget build(BuildContext context) {
    final Color signalColor = switch (status) {
      GenerationStatus.success => AppColors.success,
      GenerationStatus.failure => AppColors.error,
      GenerationStatus.idle ||
      GenerationStatus.processing => AppColors.accentPrimary,
    };

    return AspectRatio(
      aspectRatio: 350 / 420,
      child: DecoratedBox(
        key: const ValueKey<String>('processing-visual'),
        decoration: BoxDecoration(
          color: AppColors.surface1.withValues(alpha: 0.98),
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.large),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x42000000),
              offset: Offset(0, 14),
              blurRadius: 32,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.large - 1),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(
                painter: _RecognitionVisualPainter(signalColor: signalColor),
              ),
              Positioned(
                left: 58,
                right: 58,
                top: 32,
                bottom: 27,
                child: Image.asset(
                  'assets/images/photo_guide_scan_suit_front.png',
                  key: const ValueKey<String>('processing-demo-case-image'),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Text(
                  'DEMO · MOCK PROCESSING',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: signalColor,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.label});

  final GenerationStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color signalColor = switch (status) {
      GenerationStatus.success => AppColors.success,
      GenerationStatus.failure => AppColors.error,
      GenerationStatus.idle ||
      GenerationStatus.processing => AppColors.accentPrimary,
    };
    return Container(
      key: const ValueKey<String>('processing-status'),
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface1.withValues(alpha: 0.98),
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: signalColor,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: signalColor.withValues(alpha: 0.34),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ProcessingStepIndicator extends StatelessWidget {
  const _ProcessingStepIndicator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Expanded(
            child: _ProcessingStep(number: '1', label: '首页'),
          ),
          _StepTrack(color: AppColors.accentPrimary.withValues(alpha: 0.52)),
          const Expanded(
            child: _ProcessingStep(number: '2', label: '说明'),
          ),
          _StepTrack(color: AppColors.accentPrimary.withValues(alpha: 0.52)),
          const Expanded(
            child: _ProcessingStep(number: '3', label: '照片'),
          ),
          _StepTrack(color: AppColors.accentPrimary.withValues(alpha: 0.44)),
          const Expanded(
            child: _ProcessingStep(number: '4', label: '生成', isCurrent: true),
          ),
        ],
      ),
    );
  }
}

class _ProcessingStep extends StatelessWidget {
  const _ProcessingStep({
    required this.number,
    required this.label,
    this.isCurrent = false,
  });

  final String number;
  final String label;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.accentPrimary.withValues(alpha: 0.72)
                : AppColors.accentPrimary.withValues(alpha: 0.32),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: AppColors.background,
              fontFamily: 'monospace',
              fontSize: 7,
              height: 1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: isCurrent
                ? AppColors.accentPrimary
                : AppColors.textSecondary.withValues(alpha: 0.58),
            fontSize: 8,
            height: 1.3,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          isCurrent ? '当前' : '已完成',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: AppColors.textTertiary.withValues(
              alpha: isCurrent ? 0.44 : 0.58,
            ),
            fontFamily: 'monospace',
            fontSize: 6,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _StepTrack extends StatelessWidget {
  const _StepTrack({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 1,
      margin: const EdgeInsets.only(top: 10),
      color: color,
    );
  }
}

class _IncompleteProcessingView extends StatelessWidget {
  const _IncompleteProcessingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('processing-incomplete'),
      body: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 350),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    border: Border.all(color: AppColors.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadii.large),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.photo_library_outlined,
                          color: AppColors.textSecondary,
                          size: 32,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '照片尚未完整',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '请先补充正面、侧面和背面照片，再开始生成。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        PrimaryButton(
                          key: const ValueKey<String>(
                            'processing-incomplete-action',
                          ),
                          label: '返回照片选择',
                          width: double.infinity,
                          onPressed: () => context.go('/photos'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessingCopy {
  const _ProcessingCopy({
    required this.header,
    required this.headline,
    required this.supporting,
    required this.statusLabel,
    required this.footer,
  });

  factory _ProcessingCopy.forState(GenerationState state) {
    return switch (state.status) {
      GenerationStatus.idle ||
      GenerationStatus.processing => const _ProcessingCopy(
        header: 'AI 生成中',
        headline: '正在构建你的数字人体',
        supporting: '正在根据三视图照片构建数字人体\n请稍候，无需退出页面。',
        statusLabel: 'AI 生成中',
        footer: '正在准备数字人体模型 · 完成后状态将自动更新',
      ),
      GenerationStatus.success => const _ProcessingCopy(
        header: 'AI 生成',
        headline: '你的数字人体已生成',
        supporting: '数字人体已经准备完成\n现在可以进入 3D 查看',
        statusLabel: '生成完成',
        footer: '模型已经准备完成 · 可在下一步查看数字人体',
      ),
      GenerationStatus.failure => _ProcessingCopy(
        header: 'AI 生成',
        headline: '生成失败',
        supporting: state.errorMessage ?? '生成过程中出现问题，请重新尝试',
        statusLabel: '生成失败',
        footer: '照片仍然保留 · 可直接重新尝试',
      ),
    };
  }

  final String header;
  final String headline;
  final String supporting;
  final String statusLabel;
  final String footer;
}

class _RecognitionVisualPainter extends CustomPainter {
  const _RecognitionVisualPainter({required this.signalColor});

  final Color signalColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.22)
      ..strokeWidth = 0.7;
    for (double x = 0; x <= size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final Paint marker = Paint()
      ..color = signalColor.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const double inset = 22;
    const double length = 32;
    final Path corners = Path()
      ..moveTo(inset, inset + length)
      ..lineTo(inset, inset)
      ..lineTo(inset + length, inset)
      ..moveTo(size.width - inset - length, inset)
      ..lineTo(size.width - inset, inset)
      ..lineTo(size.width - inset, inset + length)
      ..moveTo(inset, size.height - inset - length)
      ..lineTo(inset, size.height - inset)
      ..lineTo(inset + length, size.height - inset)
      ..moveTo(size.width - inset - length, size.height - inset)
      ..lineTo(size.width - inset, size.height - inset)
      ..lineTo(size.width - inset, size.height - inset - length);
    canvas.drawPath(corners, marker);

    final double scanY = size.height * 0.47;
    final Paint scan = Paint()
      ..color = signalColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.09, scanY),
      Offset(size.width * 0.91, scanY),
      scan,
    );

    final Rect base = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.91),
      width: size.width * 0.63,
      height: size.height * 0.085,
    );
    canvas.drawOval(base, marker..color = signalColor.withValues(alpha: 0.92));
  }

  @override
  bool shouldRepaint(covariant _RecognitionVisualPainter oldDelegate) {
    return oldDelegate.signalColor != signalColor;
  }
}

class _ProcessingGridPainter extends CustomPainter {
  const _ProcessingGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _returnFromProcessing(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/photo-confirmation');
  }
}
