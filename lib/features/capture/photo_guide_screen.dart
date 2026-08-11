import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/primary_button.dart';

class PhotoGuideScreen extends StatelessWidget {
  const PhotoGuideScreen({super.key});

  static const List<(String, String, String)> _views =
      <(String, String, String)>[
        ('正面', 'FRONT', 'assets/images/photo_guide_scan_suit_front.png'),
        ('侧面', 'SIDE', 'assets/images/photo_guide_scan_suit_side.png'),
        ('背面', 'BACK', 'assets/images/photo_guide_scan_suit_back.png'),
      ];

  static const List<String> _requirements = <String>[
    '光线均匀，避免强逆光和明显阴影',
    '全身完整入镜，头部与双脚不要裁切',
    '身体自然站立，手臂与躯干轻微分开',
    '背景保持整洁，避免宽松或反光服装',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _GuideGridPainter()),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey<String>('photo-guide-scroll'),
                          padding: const EdgeInsets.only(top: 16, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const _GuideHeader(),
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
                                child: _GuideIntro(),
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page,
                                ),
                                child: _ThreeViewReferenceCard(views: _views),
                              ),
                              const SizedBox(height: AppSpacing.page),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page,
                                ),
                                child: _RequirementsSection(
                                  requirements: _requirements,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Align(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    child: const SizedBox(
                                      width: double.infinity,
                                      child: _StepIndicator(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: PrimaryButton(
                          key: const ValueKey<String>('photo-guide-cta'),
                          label: '我已了解',
                          width: double.infinity,
                          onPressed: () => context.push('/photos'),
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

class _GuideHeader extends StatelessWidget {
  const _GuideHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('photo-guide-back'),
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
            Text('拍摄说明', style: Theme.of(context).textTheme.titleLarge),
            if (MediaQuery.textScalerOf(context).scale(1) < 1.3) ...<Widget>[
              const Spacer(),
              Text(
                '02 / 06',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: AppColors.textTertiary.withValues(alpha: 0.82),
                  fontFamily: 'monospace',
                  fontSize: 9,
                  height: 12 / 9,
                  letterSpacing: 0.25,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideIntro extends StatelessWidget {
  const _GuideIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('按标准完成三视图拍摄', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(
          '保持自然站立，确保头部与双脚完整入镜。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _ThreeViewReferenceCard extends StatelessWidget {
  const _ThreeViewReferenceCard({required this.views});

  final List<(String, String, String)> views;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(
          color: AppColors.borderSubtle.withValues(alpha: 0.62),
        ),
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int index = 0; index < views.length; index++) ...<Widget>[
              Expanded(
                child: _ViewTile(
                  label: views[index].$1,
                  code: views[index].$2,
                  assetPath: views[index].$3,
                ),
              ),
              if (index < views.length - 1)
                const SizedBox(width: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewTile extends StatelessWidget {
  const _ViewTile({
    required this.label,
    required this.code,
    required this.assetPath,
  });

  final String label;
  final String code;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 182),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(
          color: AppColors.borderSubtle.withValues(alpha: 0.52),
        ),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 109,
            child: Image.asset(
              assetPath,
              key: ValueKey<String>('photo-guide-${code.toLowerCase()}'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: '$label人体拍摄示意',
            ),
          ),
          const SizedBox(height: 11),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$label\n',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: code,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontFamily: 'monospace',
                    fontSize: 9,
                    height: 14 / 9,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RequirementsSection extends StatelessWidget {
  const _RequirementsSection({required this.requirements});

  final List<String> requirements;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('拍摄要求', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 18,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface1.withValues(alpha: 0.74),
            border: Border.all(
              color: AppColors.borderSubtle.withValues(alpha: 0.36),
            ),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String requirement in requirements)
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '•',
                        style: TextStyle(
                          color: AppColors.accentPrimary.withValues(
                            alpha: 0.68,
                          ),
                        ),
                      ),
                      TextSpan(text: ' $requirement'),
                    ],
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 24 / 15),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator();

  static const List<(String, String)> _steps = <(String, String)>[
    ('首页', '已完成'),
    ('说明', '当前'),
    ('照片', '下一步'),
    ('生成', '稍后'),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '当前步骤：拍摄说明，第 2 步',
      child: SizedBox(
        height: 128,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _StepTrackPainter()),
            ),
            Row(
              children: <Widget>[
                for (int index = 0; index < _steps.length; index++)
                  Expanded(
                    child: _StepItem(
                      number: index + 1,
                      label: _steps[index].$1,
                      state: _steps[index].$2,
                      isReached: index <= 1,
                      isCurrent: index == 1,
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

class _StepItem extends StatelessWidget {
  const _StepItem({
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
        : AppColors.textSecondary.withValues(alpha: isReached ? 0.52 : 0.44);
    final Color circleColor = isCurrent
        ? AppColors.accentPrimary
        : isReached
        ? AppColors.accentPrimary.withValues(alpha: 0.52)
        : Colors.transparent;
    final Color numberColor = isCurrent
        ? AppColors.background
        : isReached
        ? AppColors.background.withValues(alpha: 0.68)
        : AppColors.textSecondary.withValues(alpha: 0.44);
    final Color stateColor = AppColors.textSecondary.withValues(
      alpha: isCurrent ? 0.56 : (isReached ? 0.34 : 0.26),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 17),
      child: Column(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              border: isCurrent || isReached
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
                fontSize: 10,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              height: 15 / 11,
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            state,
            style: TextStyle(
              color: stateColor,
              fontFamily: 'monospace',
              fontSize: 8,
              height: 11 / 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroLabel extends StatelessWidget {
  const _MicroLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textScaler: TextScaler.noScaling,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontFamily: 'monospace',
        fontSize: 10,
        height: 1.4,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _StepTrackPainter extends CustomPainter {
  const _StepTrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double start = size.width / 8;
    final double second = size.width * 3 / 8;
    final double end = size.width * 7 / 8;
    const double y = 30;
    canvas.drawLine(
      Offset(start, y),
      Offset(end, y),
      Paint()
        ..color = AppColors.borderSubtle.withValues(alpha: 0.30)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(start, y),
      Offset(second, y),
      Paint()
        ..color = AppColors.accentPrimary.withValues(alpha: 0.44)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GuideGridPainter extends CustomPainter {
  const _GuideGridPainter();

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

class PhotoSelectionPlaceholderScreen extends StatelessWidget {
  const PhotoSelectionPlaceholderScreen({super.key});

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
                        '三视图照片选择',
                        key: const ValueKey<String>(
                          'photo-selection-placeholder',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _MicroLabel('DAY 4 · PLACEHOLDER'),
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
