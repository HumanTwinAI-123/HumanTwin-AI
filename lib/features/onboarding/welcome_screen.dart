import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../common/info_sheets.dart';
import '../library/generation_record.dart';
import '../library/library_controller.dart';
import '../settings/app_settings.dart';

/// First launch only. No permission is requested here (v1 requests none).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool demo = ref.watch(generationModeProvider) == GenerationMode.mock;
    final TextTheme text = Theme.of(context).textTheme;
    final double heroHeight = (MediaQuery.sizeOf(context).height * 0.36).clamp(
      200,
      300,
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageBody(
                children: <Widget>[
                  const SizedBox(height: 12),
                  const Center(child: BrandLockup()),
                  const SizedBox(height: 20),
                  HeroIllustration(height: heroHeight, demo: demo),
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(
                        text: demo ? '体验用三张照片\n' : '用三张照片\n',
                        children: <InlineSpan>[
                          TextSpan(
                            text: demo ? '创建 3D 形象' : '创建你的 3D 形象',
                            style: const TextStyle(color: AppColors.brandCyan),
                          ),
                        ],
                      ),
                      style: text.displaySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '从拍摄、生成到查看与分享，一步一步完成。',
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _ValueRow(
                    icon: Icons.photo_camera_outlined,
                    title: '三张全身照',
                    body: '正面、侧面、背面各一张',
                  ),
                  _ValueRow(
                    icon: Icons.lock_outline_rounded,
                    title: '默认私密',
                    body: demo
                        ? '照片和形象只保存在这台手机上'
                        : '形象保存在这台手机上；只有提交生成时，三张照片才会发给第三方服务',
                  ),
                  const _ValueRow(
                    icon: Icons.visibility_outlined,
                    title: '分享前可预览',
                    body: '发出去的内容由你决定',
                  ),
                  const SizedBox(height: 8),
                  demo
                      ? const HtBanner(
                          tone: BannerTone.info,
                          title: '演示版说明',
                          body: '生成过程为模拟，不会上传照片；完成后得到的是示例模型，并非根据你的照片重建。',
                        )
                      : const HtBanner(
                          tone: BannerTone.info,
                          title: '生成需要上传照片',
                          body: '创建时，三张照片会发送给第三方生成服务。提交前会再次向你确认。',
                        ),
                ],
              ),
            ),
            BottomActionBar(
              children: <Widget>[
                PrimaryButton(
                  label: '开始使用',
                  hero: true,
                  onPressed: () async {
                    await ref
                        .read(appSettingsProvider.notifier)
                        .completeOnboarding();
                    if (context.mounted) {
                      context.go('/');
                    }
                  },
                ),
                LinkButton(
                  label: '查看隐私说明',
                  onPressed: () => context.push('/privacy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return IconBullet(
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );
  }
}

/// The approved brand illustration, always tagged as an illustration (never a result).
class HeroIllustration extends StatelessWidget {
  const HeroIllustration({required this.height, required this.demo, super.key});

  final double height;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.brandCyan.withValues(alpha: 0.22)),
        gradient: RadialGradient(
          radius: 0.8,
          colors: <Color>[
            AppColors.brandCyan.withValues(alpha: 0.14),
            AppColors.brandBlue.withValues(alpha: 0.07),
            AppColors.surface1,
          ],
          stops: const <double>[0, 0.45, 1],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl - 1),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              'assets/images/digital_human_hero_v2.png',
              fit: BoxFit.contain,
              semanticLabel: '3D 形象示意图',
            ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 12,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: HtChip(
                  label: demo ? '示意图 · 演示版结果为示例模型' : '示意图',
                  onMedia: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 「演示版」 qualifier banner (non-dismissible in the demo build).
class DemoQualifierBanner extends StatelessWidget {
  const DemoQualifierBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const HtBanner(
      tone: BannerTone.sample,
      title: '演示版',
      body: '生成过程为模拟，结果是示例模型，并非根据你的照片重建；照片不会上传。',
    );
  }
}

/// Tappable 「演示版」 chip with a 48dp target.
class DemoChipButton extends StatelessWidget {
  const DemoChipButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '演示版说明',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.small),
        onTap: () => showDemoInfoSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: HtChip(label: '演示版', tone: ChipTone.demo),
            ),
          ),
        ),
      ),
    );
  }
}
