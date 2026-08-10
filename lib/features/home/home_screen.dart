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
        const Positioned.fill(
          child: CustomPaint(painter: _SpatialGridPainter()),
        ),
        const Positioned(left: 20, top: 22, child: _Brand()),
        const Positioned(
          right: 20,
          top: 24,
          child: _MicroLabel('DIGITAL TWIN / DEMO'),
        ),
        const Positioned(
          left: 20,
          right: 20,
          top: 62,
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.borderSubtle,
          ),
        ),
        Positioned(
          left: 20,
          top: 82,
          child: SizedBox(
            width: 240,
            height: 68,
            child: Text(
              '创建你的\n数字人体',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 154,
          child: SizedBox(
            width: 330,
            height: 48,
            child: Text(
              '上传正面、侧面和背面照片，\n体验 AI 生成与 3D 查看流程。',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        const Positioned(right: 20, top: 88, child: _DemoBadge()),
        const Positioned(left: 20, top: 218, child: _DigitalHumanHero()),
        Positioned(
          left: 20,
          top: 656,
          child: SizedBox(
            width: 350,
            height: 20,
            child: Text(
              '三视图采集  ·  AI 生成  ·  3D 查看',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 704,
          child: PrimaryButton(
            label: '开始创建',
            onPressed: () => context.push('/photo-guide'),
          ),
        ),
        const Positioned(
          left: 20,
          top: 790,
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
    return const Text.rich(
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
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w500,
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
      width: 72,
      height: 28,
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

class _DigitalHumanHero extends StatelessWidget {
  const _DigitalHumanHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      height: 420,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface1,
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
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: CustomPaint(painter: _HeroGridPainter()),
          ),
          Positioned(
            key: const ValueKey<String>('digital-human-static-hero'),
            left: 61,
            top: 34,
            width: 228,
            height: 360,
            child: Image.asset(
              'assets/images/digital_human_hero.png',
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
          Positioned(
            left: 32,
            top: 224,
            child: Container(
              width: 286,
              height: 2,
              decoration: const BoxDecoration(
                color: Color(0x9686D7FF),
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

class _SpatialGridPainter extends CustomPainter {
  const _SpatialGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.18)
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
      ..color = AppColors.borderSubtle.withValues(alpha: 0.34)
      ..strokeWidth = 1;
    for (double x = 70; x < size.width; x += 70) {
      canvas.drawLine(Offset(x, 48), Offset(x, size.height - 48), grid);
    }
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
