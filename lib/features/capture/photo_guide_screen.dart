import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../common/info_sheets.dart';
import '../settings/app_settings.dart';
import 'photo_flow_controller.dart';

const Map<PhotoAngle, String> angleLabels = <PhotoAngle, String>{
  PhotoAngle.front: '正面',
  PhotoAngle.side: '侧面',
  PhotoAngle.back: '背面',
};

const Map<PhotoAngle, String> guideImages = <PhotoAngle, String>{
  PhotoAngle.front: 'assets/images/photo_guide_scan_suit_front.png',
  PhotoAngle.side: 'assets/images/photo_guide_scan_suit_side.png',
  PhotoAngle.back: 'assets/images/photo_guide_scan_suit_back.png',
};

/// 拍摄说明 (step 1/3). `?mode=back` returns to the photos page, `?mode=view` is read-only.
class PhotoGuideScreen extends ConsumerStatefulWidget {
  const PhotoGuideScreen({super.key});

  @override
  ConsumerState<PhotoGuideScreen> createState() => _PhotoGuideScreenState();
}

class _PhotoGuideScreenState extends ConsumerState<PhotoGuideScreen> {
  bool _skipNextTime = false;

  @override
  Widget build(BuildContext context) {
    final String mode =
        GoRouterState.of(context).uri.queryParameters['mode'] ?? 'create';
    final bool creating = mode == 'create';
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: HtAppBar(title: '拍摄说明', step: creating ? (1, 3) : null),
      body: PageBody(
        children: <Widget>[
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text('拍出更好的效果', style: text.headlineMedium),
          ),
          const SizedBox(height: 4),
          Text('正面、侧面、背面各一张全身照，自然站立，头部和双脚完整入镜。', style: text.bodyMedium),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              for (final PhotoAngle angle in PhotoAngle.values) ...<Widget>[
                if (angle != PhotoAngle.front) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      AspectRatio(
                        aspectRatio: 4 / 5,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(
                              AppRadii.medium,
                            ),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Image.asset(
                            guideImages[angle]!,
                            fit: BoxFit.contain,
                            semanticLabel: '${angleLabels[angle]}参考示例',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        angleLabels[angle]!,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SectionHeader(title: '拍摄要求'),
          const HtCard(
            child: Column(
              children: <Widget>[
                IconBullet(
                  icon: Icons.light_mode_outlined,
                  child: Text('光线均匀，避免强逆光和明显阴影'),
                ),
                IconBullet(
                  icon: Icons.crop_free_rounded,
                  child: Text('全身完整入镜，头部与双脚不要裁切'),
                ),
                IconBullet(
                  icon: Icons.accessibility_new_rounded,
                  child: Text('身体自然站立，手臂与躯干轻微分开'),
                ),
                IconBullet(
                  icon: Icons.checkroom_rounded,
                  child: Text('背景整洁，避免宽松或反光的衣服'),
                ),
                IconBullet(
                  icon: Icons.back_hand_outlined,
                  child: Text('请他人帮忙拍摄，或把手机固定在腰部高度并使用定时拍摄'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const HtBanner(
            tone: BannerTone.neutral,
            icon: Icons.person_outline_rounded,
            body: '请只使用你本人，或已获得本人同意的照片。未满 14 周岁请在监护人同意并陪同下使用。',
          ),
          if (creating)
            CheckboxListTile(
              value: _skipNextTime,
              onChanged: (bool? value) =>
                  setState(() => _skipNextTime = value ?? false),
              title: Text(
                '下次不再显示拍摄说明',
                style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        children: <Widget>[
          PrimaryButton(
            label: creating ? '开始选择照片' : '知道了',
            onPressed: () async {
              if (!creating) {
                context.pop();
                return;
              }
              if (_skipNextTime) {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setShowGuide(false);
              }
              if (context.mounted) {
                context.pushReplacement('/create/photos');
              }
            },
          ),
        ],
      ),
    );
  }
}
