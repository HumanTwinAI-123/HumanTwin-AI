import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

// Shared components of the v1 design system. Screens compose only these and theme widgets.

/// Page app bar: back (or close), single-line title, optional step counter and actions.
class HtAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HtAppBar({
    this.title,
    this.titleWidget,
    this.step,
    this.actions = const <Widget>[],
    this.close = false,
    this.showBack = true,
    this.onBack,
    super.key,
  });

  final String? title;
  final Widget? titleWidget;

  /// (current, total), e.g. (2, 3) → 「2 / 3」.
  final (int, int)? step;
  final List<Widget> actions;
  final bool close;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final (int, int)? step = this.step;
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: showBack ? 4 : AppSpacing.gutter(context),
      leading: showBack
          ? IconButton(
              tooltip: close ? '关闭' : '返回',
              icon: Icon(
                close ? Icons.close_rounded : Icons.arrow_back_rounded,
              ),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            )
          : null,
      title:
          titleWidget ??
          Semantics(
            header: true,
            child: Text(
              title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      actions: <Widget>[
        if (step != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              child: Semantics(
                label: '第 ${step.$1} 步，共 ${step.$2} 步',
                excludeSemantics: true,
                child: Text(
                  '${step.$1} / ${step.$2}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ...actions,
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Fixed-size brand lockup (the one element that does not scale with system text).
class BrandLockup extends StatelessWidget {
  const BrandLockup({this.markSize = 32, this.showMark = true, super.key});

  final double markSize;

  /// The wordmark alone (e.g. under a large standalone mark).
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'HumanTwin AI',
      excludeSemantics: true,
      child: MediaQuery.withNoTextScaling(
        // Shrinks (never overflows) when the toolbar leaves less room, e.g. 360 dp + 演示版.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showMark) ...<Widget>[
                Image.asset(
                  'assets/images/brand/humantwin_mark.png',
                  width: markSize,
                  height: markSize,
                ),
                const SizedBox(width: 10),
              ],
              const Text.rich(
                TextSpan(
                  text: 'HumanTwin ',
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'AI',
                      style: TextStyle(color: AppColors.brandCyan),
                    ),
                  ],
                ),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom action area (primary action + optional secondary + hint).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    required this.children,
    this.border = true,
    super.key,
  });

  final List<Widget> children;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: border
            ? Border(
                top: BorderSide(
                  color: AppColors.borderSubtle.withValues(alpha: 0.6),
                ),
              )
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.gutter(context),
            AppSpacing.md,
            AppSpacing.gutter(context),
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _spaced(children, AppSpacing.sm),
          ),
        ),
      ),
    );
  }
}

/// Centred hint text under bottom actions.
class ActionHint extends StatelessWidget {
  const ActionHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

List<Widget> _spaced(List<Widget> children, double gap) {
  final List<Widget> out = <Widget>[];
  for (final Widget child in children) {
    if (out.isNotEmpty) {
      out.add(SizedBox(height: gap));
    }
    out.add(child);
  }
  return out;
}

/// Full-width primary button with optional leading icon or a loading spinner.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.hero = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: hero
          ? FilledButton.styleFrom(
              minimumSize: const Size(64, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.large),
              ),
            )
          : null,
      child: _ButtonContent(label: label, icon: icon, loading: loading),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: _ButtonContent(label: label, icon: icon),
    );
  }
}

class TonalButton extends StatelessWidget {
  const TonalButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: danger
            ? AppColors.tint(AppColors.error)
            : AppColors.tonalBackground,
        foregroundColor: danger ? AppColors.error : AppColors.tonalForeground,
      ),
      child: _ButtonContent(label: label, icon: icon),
    );
  }
}

class LinkButton extends StatelessWidget {
  const LinkButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: danger
          ? TextButton.styleFrom(foregroundColor: AppColors.error)
          : null,
      child: _ButtonContent(label: label, icon: icon, iconSize: 18),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    this.icon,
    this.loading = false,
    this.iconSize = 20,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Widget? leading = loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon == null
        ? null
        : Icon(icon, size: iconSize);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (leading != null) ...<Widget>[leading, const SizedBox(width: 8)],
        Flexible(
          child: Text(label, textAlign: TextAlign.center, softWrap: true),
        ),
      ],
    );
  }
}

/// Two buttons side by side; stacked at large text.
class ButtonPair extends StatelessWidget {
  const ButtonPair({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[first, const SizedBox(height: 8), second],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: first),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: second),
      ],
    );
  }
}

enum ChipTone {
  neutral,
  processing,
  queued,
  success,
  warning,
  danger,
  info,
  sample,
  ai,
  demo,
}

/// Status / origin chip. Colour is always paired with words (and usually an icon).
class HtChip extends StatelessWidget {
  const HtChip({
    required this.label,
    this.tone = ChipTone.neutral,
    this.icon,
    this.dot = false,
    this.onMedia = false,
    this.large = false,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final ChipTone tone;
  final IconData? icon;
  final bool dot;
  final bool onMedia;
  final bool large;
  final String? semanticLabel;

  (Color, Color) get _colors => switch (tone) {
    ChipTone.neutral => (AppColors.surface3, AppColors.textSecondary),
    ChipTone.processing => (
      AppColors.tint(AppColors.processing, 0.12),
      const Color(0xFF7FEEFF),
    ),
    ChipTone.queued => (
      AppColors.tint(AppColors.brandBlue, 0.18),
      const Color(0xFFA6C4FF),
    ),
    ChipTone.success => (AppColors.tint(AppColors.success), AppColors.success),
    ChipTone.warning => (AppColors.tint(AppColors.warning), AppColors.warning),
    ChipTone.danger => (AppColors.tint(AppColors.error), AppColors.error),
    ChipTone.info => (
      AppColors.tint(AppColors.accentPrimary, 0.12),
      AppColors.accentPrimary,
    ),
    ChipTone.sample => (
      AppColors.originSampleBackground,
      AppColors.originSampleForeground,
    ),
    ChipTone.ai => (AppColors.originAiBackground, AppColors.originAiForeground),
    ChipTone.demo => (Colors.transparent, AppColors.brandCyan),
  };

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = _colors;
    final TextStyle style = TextStyle(
      color: foreground,
      fontSize: large ? 14 : 12,
      height: 1.35,
      fontWeight: FontWeight.w600,
    );
    Widget chip = Container(
      constraints: BoxConstraints(minHeight: large ? 32 : 26),
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 10, vertical: 3),
      decoration: BoxDecoration(
        color: onMedia && tone != ChipTone.demo
            ? Color.alphaBlend(background, const Color(0xC70A0E14))
            : background,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: tone == ChipTone.demo
            ? Border.all(color: AppColors.brandCyan.withValues(alpha: 0.45))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dot) ...<Widget>[
            _PulsingDot(color: foreground),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(child: Text(label, style: style)),
        ],
      ),
    );
    if (onMedia) {
      // Overlays on media cap at 130%; the same facts are repeated as text in large layouts.
      chip = MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: chip,
      );
    }
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: chip,
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

enum BannerTone { info, success, warning, danger, sample, neutral }

class HtBanner extends StatelessWidget {
  const HtBanner({
    required this.tone,
    this.title,
    this.body,
    this.icon,
    this.actions = const <Widget>[],
    super.key,
  });

  final BannerTone tone;
  final String? title;
  final String? body;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final (
      Color background,
      Color iconColor,
      IconData defaultIcon,
    ) = switch (tone) {
      BannerTone.info => (
        AppColors.tint(AppColors.accentPrimary, 0.12),
        AppColors.accentPrimary,
        Icons.info_outline_rounded,
      ),
      BannerTone.success => (
        AppColors.tint(AppColors.success),
        AppColors.success,
        Icons.check_circle_outline_rounded,
      ),
      BannerTone.warning => (
        AppColors.tint(AppColors.warning),
        AppColors.warning,
        Icons.warning_amber_rounded,
      ),
      BannerTone.danger => (
        AppColors.tint(AppColors.error),
        AppColors.error,
        Icons.error_outline_rounded,
      ),
      BannerTone.sample => (
        AppColors.originSampleBackground,
        AppColors.originSampleForeground,
        Icons.view_in_ar_rounded,
      ),
      BannerTone.neutral => (
        AppColors.surface2,
        AppColors.textSecondary,
        Icons.info_outline_rounded,
      ),
    };
    final TextTheme text = Theme.of(context).textTheme;
    final Widget content = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? defaultIcon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null)
                  Text(
                    title!,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (body != null)
                  Text(
                    body!,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                if (actions.isNotEmpty)
                  Wrap(spacing: 4, runSpacing: 0, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
    final bool alert = tone == BannerTone.warning || tone == BannerTone.danger;
    return Semantics(container: true, liveRegion: alert, child: content);
  }
}

enum FactTone { plain, ok, warn, bad }

class FactRow {
  const FactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.tone = FactTone.plain,
  });

  final IconData icon;
  final String label;
  final String value;
  final FactTone tone;
}

/// The "what we know" table on recovery pages (任务 / 额度 / 照片 …). Stacks at large text.
class FactTable extends StatelessWidget {
  const FactTable({required this.rows, super.key});

  final List<FactRow> rows;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool large = isLargeText(context);
    final double labelWidth = large ? 0 : _labelWidth(context, text.bodyMedium);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _factRow(rows[i], text, large, labelWidth),
            ),
          ],
        ],
      ),
    );
  }

  /// The widest label at the current text size, so labels never break mid-word.
  double _labelWidth(BuildContext context, TextStyle? style) {
    double widest = 0;
    for (final FactRow row in rows) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: row.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = widest < painter.width ? painter.width : widest;
      painter.dispose();
    }
    return widest.ceilToDouble().clamp(48, 120);
  }

  Widget _factRow(FactRow row, TextTheme text, bool large, double labelWidth) {
    final Color valueColor = switch (row.tone) {
      FactTone.plain => AppColors.textPrimary,
      FactTone.ok => AppColors.success,
      FactTone.warn => AppColors.warning,
      FactTone.bad => AppColors.error,
    };
    final Widget icon = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(row.icon, size: 20, color: AppColors.textSecondary),
    );
    final Text label = Text(row.label, style: text.bodyMedium);
    final Text value = Text(
      row.value,
      style: text.bodyMedium?.copyWith(color: valueColor),
    );
    return MergeSemantics(
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[icon, const SizedBox(width: 12), label]),
                const SizedBox(height: 2),
                value,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                icon,
                const SizedBox(width: 12),
                SizedBox(width: labelWidth, child: label),
                const SizedBox(width: 8),
                Expanded(child: value),
              ],
            ),
    );
  }
}

/// Card surface.
class HtCard extends StatelessWidget {
  const HtCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradientBorder = false,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool gradientBorder;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppRadii.large);
    Widget inner = Material(
      color: AppColors.surface1,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (gradientBorder) {
      inner = DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: radius,
        ),
        child: Padding(padding: const EdgeInsets.all(1), child: inner),
      );
    } else {
      inner = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: radius,
        ),
        position: DecorationPosition.foreground,
        child: inner,
      );
    }
    if (onTap != null || semanticLabel != null) {
      inner = Semantics(
        button: onTap != null,
        label: semanticLabel,
        child: inner,
      );
    }
    return inner;
  }
}

/// A list row (settings, menus). The whole row is the touch target.
class HtListItem extends StatelessWidget {
  const HtListItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.tinted = false,
    this.chevron = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool tinted;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color titleColor = danger ? AppColors.error : AppColors.textPrimary;
    final Widget? lead = icon == null
        ? null
        : tinted
        ? Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tonalBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppColors.tonalForeground),
          )
        : Icon(
            icon,
            size: 24,
            color: danger ? AppColors.error : AppColors.textSecondary,
          );
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              if (lead != null) ...<Widget>[lead, const SizedBox(width: 16)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(color: titleColor),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: text.bodyMedium),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ] else if (chevron && onTap != null) ...<Widget>[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Group of list rows inside a bordered surface.
class HtListGroup extends StatelessWidget {
  const HtListGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.large),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1, indent: 56),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class ListHeading extends StatelessWidget {
  const ListHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Empty state: dashed 4:5 frame with the brand mark, title, body and actions.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 32, 8, 24),
      child: Column(
        children: <Widget>[
          Container(
            width: 132,
            height: 165,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: AppColors.borderStrong, width: 1.5),
              gradient: LinearGradient(
                colors: <Color>[
                  AppColors.brandCyan.withValues(alpha: 0.16),
                  AppColors.brandBlue.withValues(alpha: 0.1),
                  AppColors.brandViolet.withValues(alpha: 0.16),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/images/brand/humantwin_mark.png',
                width: 76,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _spaced(actions, AppSpacing.sm),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum StatusTone { success, warning, danger, info, neutral }

/// Icon tile + title + body at the top of result and recovery pages.
class StatusHero extends StatelessWidget {
  const StatusHero({
    required this.tone,
    required this.icon,
    required this.title,
    this.body,
    super.key,
  });

  final StatusTone tone;
  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (tone) {
      StatusTone.success => AppColors.success,
      StatusTone.warning => AppColors.warning,
      StatusTone.danger => AppColors.error,
      StatusTone.info => AppColors.accentPrimary,
      StatusTone.neutral => AppColors.textSecondary,
    };
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: tone == StatusTone.neutral
                  ? AppColors.surface2
                  : AppColors.tint(color),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 34, color: color),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              title,
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(body!, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Brand-gradient progress ring; null progress → indeterminate spin.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    required this.progress,
    this.size = 56,
    this.stroke = 5,
    this.showLabel = true,
    super.key,
  });

  /// 0–100, or null when unknown.
  final int? progress;
  final double size;
  final double stroke;
  final bool showLabel;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool animate =
        widget.progress == null && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!animate && _spin.isAnimating) {
      // Determinate progress starts at 12 o'clock, not at the angle the spinner stopped.
      _spin.reset();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int? progress = widget.progress;
    return Semantics(
      label: progress == null ? '进行中' : '进度 $progress%',
      value: progress == null ? null : '$progress%',
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            RotationTransition(
              turns: _spin,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPainter(
                  fraction: progress == null ? 0.28 : progress / 100,
                  stroke: widget.stroke,
                ),
              ),
            ),
            if (progress != null && widget.showLabel)
              ExcludeSemantics(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    '$progress%',
                    style: TextStyle(
                      fontSize: widget.size >= 100 ? 22 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
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

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.stroke});

  final double fraction;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(stroke / 2 + 1);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = AppColors.textPrimary.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (fraction <= 0) {
      return;
    }
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      Paint()
        ..shader = const SweepGradient(
          colors: <Color>[
            AppColors.brandCyan,
            AppColors.brandBlue,
            AppColors.brandViolet,
            AppColors.brandCyan,
          ],
          stops: <double>[0, 0.45, 0.85, 1],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.stroke != stroke;
}

/// Linear brand progress bar; null value → indeterminate.
class BrandProgressBar extends StatelessWidget {
  const BrandProgressBar({required this.value, super.key});

  final int? value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: value == null ? null : value! / 100,
          color: AppColors.brandBlue,
          backgroundColor: AppColors.surface3,
        ),
      ),
    );
  }
}

enum StageState { done, active, pending, warn, fail }

class Stage {
  const Stage(this.title, this.state, {this.subtitle});

  final String title;
  final StageState state;
  final String? subtitle;
}

/// Vertical stage list on the progress page.
class StageList extends StatelessWidget {
  const StageList({required this.stages, super.key});

  final List<Stage> stages;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        for (int i = 0; i < stages.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 24,
                  child: Column(
                    children: <Widget>[
                      _pip(stages[i].state),
                      if (i < stages.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: stages[i].state == StageState.done
                                ? AppColors.success.withValues(alpha: 0.5)
                                : AppColors.borderSubtle,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < stages.length - 1 ? 16 : 0,
                    ),
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            stages[i].title,
                            style: text.bodyLarge?.copyWith(
                              color: stages[i].state == StageState.pending
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                            semanticsLabel:
                                '${stages[i].title}，${_stateLabel(stages[i].state)}',
                          ),
                          if (stages[i].subtitle != null)
                            Text(stages[i].subtitle!, style: text.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _stateLabel(StageState state) => switch (state) {
    StageState.done => '已完成',
    StageState.active => '进行中',
    StageState.pending => '未开始',
    StageState.warn => '需要处理',
    StageState.fail => '未成功',
  };

  Widget _pip(StageState state) {
    final (Color border, Color fill, Widget? child) = switch (state) {
      StageState.done => (
        AppColors.success,
        AppColors.success,
        const Icon(Icons.check_rounded, size: 14, color: Color(0xFF07140E)),
      ),
      StageState.active => (
        AppColors.processing,
        AppColors.background,
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.processing,
            shape: BoxShape.circle,
          ),
        ),
      ),
      StageState.pending => (
        AppColors.borderStrong,
        AppColors.background,
        null,
      ),
      StageState.warn => (
        AppColors.warning,
        AppColors.warning,
        const Icon(
          Icons.priority_high_rounded,
          size: 13,
          color: Color(0xFF1B1203),
        ),
      ),
      StageState.fail => (
        AppColors.error,
        AppColors.error,
        const Icon(Icons.close_rounded, size: 13, color: Color(0xFF1B0808)),
      ),
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Sheet title + optional subtitle.
class SheetHeader extends StatelessWidget {
  const SheetHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter(context),
        0,
        AppSpacing.gutter(context),
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(header: true, child: Text(title, style: text.titleLarge)),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(subtitle!, style: text.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Opens a modal bottom sheet in the house style (scrollable, safe-area aware).
Future<T?> showHtSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: builder(sheetContext),
      ),
    ),
  );
}

/// Padding for content inside a sheet.
class SheetBody extends StatelessWidget {
  const SheetBody({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter(context)),
      child: child,
    );
  }
}

/// Confirmation dialog. Returns true only when the confirming action is chosen.
Future<bool> showHtConfirm(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
  IconData? icon,
}) async {
  final bool? result = await showHtChoice(
    context,
    title: title,
    paragraphs: paragraphs,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    destructive: destructive,
    icon: icon,
  );
  return result ?? false;
}

/// Like [showHtConfirm] when the cancel button is itself an action: true (confirm),
/// false (the cancel-labelled action), or null when dismissed with back or the scrim.
Future<bool?> showHtChoice(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
  IconData? icon,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final TextTheme text = Theme.of(dialogContext).textTheme;
      return AlertDialog(
        icon: icon == null
            ? null
            : Icon(icon, color: AppColors.textSecondary, size: 26),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String paragraph in paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(paragraph, style: text.bodyMedium),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: AppColors.error)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

/// One-line snackbar with an optional action (replaces the current one).
void showHtSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// Page body padding with the responsive gutter and a centred max width.
class PageBody extends StatelessWidget {
  const PageBody({required this.children, this.controller, super.key});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final double gutter = AppSpacing.gutter(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          controller: controller,
          // Edge-to-edge: keep the last item above the system navigation bar. Pages with a
          // bottom bar already have this inset removed by their Scaffold.
          padding: EdgeInsets.fromLTRB(
            gutter,
            0,
            gutter,
            AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: children,
        ),
      ),
    );
  }
}
