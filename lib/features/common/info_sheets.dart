import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/ht_ui.dart';
import '../library/generation_record.dart';

/// Bullet row with a leading icon (sheets, cards).
class IconBullet extends StatelessWidget {
  const IconBullet({required this.icon, required this.child, super.key});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: AppColors.accentPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「关于演示版」: what the simulation does and does not do.
Future<void> showDemoInfoSheet(BuildContext context) {
  return showHtSheet<void>(context, (BuildContext sheetContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(title: '关于演示版'),
        const SheetBody(
          child: Column(
            children: <Widget>[
              IconBullet(
                icon: Icons.hourglass_empty_rounded,
                child: Text('「生成」是模拟流程，用来体验完整步骤，约需 5 秒。'),
              ),
              IconBullet(
                icon: Icons.view_in_ar_rounded,
                child: Text('完成后得到的是内置示例模型，并非根据你的照片重建，所有形象看起来都一样。'),
              ),
              IconBullet(
                icon: Icons.lock_outline_rounded,
                child: Text('照片不会上传，也不会产生任何费用。'),
              ),
              IconBullet(
                icon: Icons.info_outline_rounded,
                child: Text('将来接入真实生成服务时，上传照片前会单独征得你的同意。'),
              ),
            ],
          ),
        ),
        SheetBody(
          child: PrimaryButton(
            label: '知道了',
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ],
    );
  });
}

/// 「生成方式」 (read-only: the build decides the mode).
Future<void> showModeInfoSheet(BuildContext context, GenerationMode mode) {
  final bool demo = mode == GenerationMode.mock;
  return showHtSheet<void>(context, (BuildContext sheetContext) {
    final TextTheme text = Theme.of(sheetContext).textTheme;
    Widget option(String title, String body, bool current, String tag) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: current ? AppColors.accentPrimary : AppColors.borderSubtle,
            width: current ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(body, style: text.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            HtChip(
              label: tag,
              tone: current ? ChipTone.info : ChipTone.neutral,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(title: '生成方式'),
        SheetBody(
          child: Column(
            children: <Widget>[
              option(
                '模拟生成（演示版）',
                '完整体验流程，不上传照片、不消耗额度。结果是内置示例模型，并非根据你的照片重建。',
                demo,
                demo ? '当前' : '本版本未启用',
              ),
              option(
                demo ? '第三方生成服务' : '本地测试服务（开发用）',
                demo
                    ? '尚未接入。接入后，上传照片前会单独征得你的同意。'
                    : '开发版本：照片经本机测试代理交给第三方生成服务，每次提交消耗 1 次生成额度。结果标注为「AI 生成」。',
                !demo,
                demo ? '未接入' : '当前',
              ),
            ],
          ),
        ),
        SheetBody(
          child: PrimaryButton(
            label: '知道了',
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ],
    );
  });
}
