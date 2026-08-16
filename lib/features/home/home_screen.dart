import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/primary_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Size designSize = Size(390, 844);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double canvasWidth = constraints.maxWidth.clamp(
                0,
                designSize.width,
              );
              final double scale = canvasWidth / designSize.width;

              return SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: canvasWidth,
                    height: designSize.height * scale,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox.fromSize(
                        size: designSize,
                        child: const _HomeCanvas(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeCanvas extends StatelessWidget {
  const _HomeCanvas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned(
          left: 46,
          right: 46,
          top: 152,
          height: 470,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: <Color>[
                  Color(0x1F86D7FF),
                  Color(0x0A2979FF),
                  Color(0x00090D12),
                ],
                stops: <double>[0, 0.54, 1],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: CustomPaint(painter: _SpatialGridPainter()),
        ),
        const Positioned(left: 20, top: 18, child: _Brand()),
        const Positioned(right: 20, top: 24, child: _DemoBadge()),
        const Positioned(
          left: 20,
          right: 20,
          top: 73,
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.borderSubtle,
          ),
        ),
        Positioned(
          left: 20,
          top: 91,
          child: SizedBox(
            width: 350,
            height: 72,
            child: Text.rich(
              const TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: '创建你的\n'),
                  TextSpan(
                    text: '数字人体',
                    style: TextStyle(color: AppColors.accentPrimary),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 30,
                height: 1.12,
                letterSpacing: -0.7,
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 170,
          child: SizedBox(
            width: 350,
            height: 48,
            child: Text(
              '上传正面、侧面和背面照片，\n体验 AI 生成与 3D 查看流程。',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.55),
            ),
          ),
        ),
        const Positioned(left: 20, top: 231, child: _DigitalHumanHero()),
        const Positioned(left: 20, top: 641, child: _FlowSummary()),
        Positioned(
          left: 20,
          top: 701,
          child: PrimaryButton(
            label: '开始创建',
            onPressed: () => context.push('/photo-guide'),
          ),
        ),
        const Positioned(
          left: 20,
          top: 789,
          child: SizedBox(
            width: 350,
            child: _MicroLabel(
              'FRONTEND DEMO  ·  MOCK AI  ·  LOCAL GLB',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'HumanTwin AI',
      child: ExcludeSemantics(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset(
                'assets/images/brand/humantwin_mark.png',
                key: const ValueKey<String>('humantwin-brand-mark'),
                width: 32,
                height: 32,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 10),
              const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: 'HumanTwin',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                        TextSpan(
                          text: ' AI',
                          style: TextStyle(color: AppColors.accentPrimary),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.05,
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'DIGITAL HUMAN · SMARTER LIFE',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontFamily: 'monospace',
                      fontSize: 7,
                      height: 1,
                      letterSpacing: 1.15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicroLabel extends StatelessWidget {
  const _MicroLabel(this.text, {this.textAlign = TextAlign.right});

  final String text;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: const TextStyle(
        color: AppColors.textTertiary,
        fontFamily: 'monospace',
        fontSize: 10,
        height: 1.4,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: const Text(
        'DEMO',
        style: TextStyle(
          color: AppColors.accentPrimary,
          fontFamily: 'monospace',
          fontSize: 10,
          height: 1.4,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FlowSummary extends StatelessWidget {
  const _FlowSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface1.withValues(alpha: 0.82),
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _FlowStep('三视图采集'),
            _FlowDivider(),
            _FlowStep('AI 生成'),
            _FlowDivider(),
            _FlowStep('3D 查看'),
          ],
        ),
      ),
    );
  }
}

class _FlowStep extends StatelessWidget {
  const _FlowStep(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: AppColors.accentPrimary,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(color: Color(0x6686D7FF), blurRadius: 5),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FlowDivider extends StatelessWidget {
  const _FlowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 11),
      child: SizedBox(
        width: 1,
        height: 14,
        child: ColoredBox(color: AppColors.borderSubtle),
      ),
    );
  }
}

class _DigitalHumanHero extends StatelessWidget {
  const _DigitalHumanHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      height: 390,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF131C25), Color(0xFF0B1118)],
        ),
        border: Border.all(color: const Color(0x665B91AB)),
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x42000000),
            offset: Offset(0, 14),
            blurRadius: 32,
          ),
          BoxShadow(color: Color(0x1886D7FF), blurRadius: 24),
        ],
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            left: 62,
            right: 62,
            top: 46,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[
                    Color(0x2486D7FF),
                    Color(0x0F2979FF),
                    Color(0x000B1118),
                  ],
                  stops: <double>[0, 0.58, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: CustomPaint(painter: _HeroGridPainter()),
          ),
          Positioned(
            key: const ValueKey<String>('digital-human-static-hero'),
            left: 53,
            top: 26,
            width: 244,
            height: 350,
            child: Image.asset(
              'assets/images/digital_human_hero_v2.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: '数字人体静态预览',
            ),
          ),
          const Positioned(
            left: 16,
            top: 14,
            child: Text(
              'DIGITAL HUMAN / STATIC PREVIEW',
              style: TextStyle(
                color: AppColors.accentPrimary,
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.4,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Positioned(
            right: 16,
            top: 14,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StatusDot(),
                SizedBox(width: 6),
                Text(
                  'STATIC PROFILE',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontFamily: 'monospace',
                    fontSize: 9,
                    height: 1.4,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 188,
            height: 34,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x0086D7FF),
                    Color(0x2686D7FF),
                    Color(0x0086D7FF),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 204,
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0x0086D7FF),
                    Color(0xCC86D7FF),
                    Color(0x0086D7FF),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Color(0x4786D7FF), blurRadius: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        color: AppColors.accentPrimary,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x9986D7FF), blurRadius: 6),
        ],
      ),
    );
  }
}

class _SpatialGridPainter extends CustomPainter {
  const _SpatialGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.14)
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

class _HeroGridPainter extends CustomPainter {
  const _HeroGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.38)
      ..strokeWidth = 1;
    for (double x = 70; x < size.width; x += 70) {
      canvas.drawLine(Offset(x, 48), Offset(x, size.height - 48), grid);
    }

    final Paint axis = Paint()
      ..color = AppColors.accentPrimary.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 48),
      Offset(size.width / 2, size.height - 28),
      axis,
    );
    for (double y = 84; y < size.height - 40; y += 52) {
      canvas.drawLine(Offset(36, y), Offset(size.width - 36, y), grid);
    }

    final Paint accent = Paint()
      ..color = AppColors.accentPrimary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - 35),
        width: 220,
        height: 38,
      ),
      accent,
    );
    const double edge = 22;
    for (final (Offset start, Offset middle, Offset end)
        in <(Offset, Offset, Offset)>[
          (
            const Offset(edge, 54),
            const Offset(edge, edge),
            const Offset(54, edge),
          ),
          (
            Offset(size.width - 54, edge),
            Offset(size.width - edge, edge),
            Offset(size.width - edge, 54),
          ),
          (
            Offset(edge, size.height - 54),
            Offset(edge, size.height - edge),
            Offset(54, size.height - edge),
          ),
          (
            Offset(size.width - 54, size.height - edge),
            Offset(size.width - edge, size.height - edge),
            Offset(size.width - edge, size.height - 54),
          ),
        ]) {
      canvas.drawLine(start, middle, accent);
      canvas.drawLine(middle, end, accent);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
