import 'dart:typed_data';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';

enum PhotoSlotState { empty, filled, error }

class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    required this.label,
    required this.englishLabel,
    required this.image,
    required this.state,
    required this.onPick,
    required this.onReplace,
    required this.onRemove,
    this.placeholderAsset,
    super.key,
  });

  final String label;
  final String englishLabel;
  final XFile? image;
  final PhotoSlotState state;
  final VoidCallback onPick;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final String? placeholderAsset;

  @override
  Widget build(BuildContext context) {
    final VoidCallback onTap = state == PhotoSlotState.filled
        ? onReplace
        : onPick;
    final Color borderColor = switch (state) {
      PhotoSlotState.empty => AppColors.accentPrimary.withValues(alpha: 0.72),
      PhotoSlotState.filled => AppColors.borderSubtle.withValues(alpha: 0.82),
      PhotoSlotState.error => AppColors.error.withValues(alpha: 0.78),
    };
    final String stateLabel = switch (state) {
      PhotoSlotState.empty => '等待添加',
      PhotoSlotState.filled => '已添加，点击可替换',
      PhotoSlotState.error => '照片异常，点击重新选择',
    };

    return Semantics(
      container: true,
      button: true,
      label: '$label，$englishLabel，$stateLabel',
      customSemanticsActions: state == PhotoSlotState.filled
          ? <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(label: '删除$label照片'): onRemove,
            }
          : const <CustomSemanticsAction, VoidCallback>{},
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 154),
        child: CustomPaint(
          foregroundPainter: _PhotoSlotBorderPainter(
            color: borderColor,
            dashed: state == PhotoSlotState.empty,
          ),
          child: Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: state == PhotoSlotState.filled ? onRemove : null,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _PhotoSlotPreview(
                      label: label,
                      image: image,
                      placeholderAsset: placeholderAsset,
                      state: state,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _PhotoSlotCopy(
                          label: label,
                          englishLabel: englishLabel,
                          state: state,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 38,
                      height: 126,
                      child: Align(child: _PhotoSlotStatus(state: state)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSlotPreview extends StatelessWidget {
  const _PhotoSlotPreview({
    required this.label,
    required this.image,
    required this.placeholderAsset,
    required this.state,
  });

  final String label;
  final XFile? image;
  final String? placeholderAsset;
  final PhotoSlotState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 102,
      height: 126,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: switch (state) {
          PhotoSlotState.filled =>
            image == null
                ? const _ImageFallback()
                : _XFilePreview(image: image!, semanticLabel: '$label照片'),
          PhotoSlotState.empty => _PlaceholderPreview(
            assetPath: placeholderAsset,
            semanticLabel: '$label拍摄占位示意',
          ),
          PhotoSlotState.error => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Opacity(
                opacity: 0.34,
                child: _PlaceholderPreview(
                  assetPath: placeholderAsset,
                  semanticLabel: '$label拍摄占位示意',
                ),
              ),
              const ColoredBox(color: Color(0x1FFF8D8D)),
              const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.error,
                  size: 26,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _XFilePreview extends StatefulWidget {
  const _XFilePreview({required this.image, required this.semanticLabel});

  final XFile image;
  final String semanticLabel;

  @override
  State<_XFilePreview> createState() => _XFilePreviewState();
}

class _XFilePreviewState extends State<_XFilePreview> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.image.readAsBytes();
  }

  @override
  void didUpdateWidget(covariant _XFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) {
      _bytes = widget.image.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.requireData,
            key: ValueKey<String>('photo-slot-image-${widget.image.path}'),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            cacheWidth: 512,
            semanticLabel: widget.semanticLabel,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) {
                  return const _ImageFallback();
                },
          );
        }
        if (snapshot.hasError) {
          return const _ImageFallback();
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
    );
  }
}

class _PlaceholderPreview extends StatelessWidget {
  const _PlaceholderPreview({
    required this.assetPath,
    required this.semanticLabel,
  });

  final String? assetPath;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (assetPath != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Image.asset(
          assetPath!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: semanticLabel,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return const _ImageFallback();
              },
        ),
      );
    }
    return const _ImageFallback();
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.accessibility_new_rounded,
        color: AppColors.textTertiary,
        size: 42,
      ),
    );
  }
}

class _PhotoSlotCopy extends StatelessWidget {
  const _PhotoSlotCopy({
    required this.label,
    required this.englishLabel,
    required this.state,
  });

  final String label;
  final String englishLabel;
  final PhotoSlotState state;

  @override
  Widget build(BuildContext context) {
    final Color supportingColor = state == PhotoSlotState.error
        ? AppColors.error.withValues(alpha: 0.9)
        : AppColors.textSecondary;
    final String supportingText = switch (state) {
      PhotoSlotState.empty => '$englishLabel · 添加照片\n相册或拍摄 · 4:5',
      PhotoSlotState.filled => '$englishLabel · 已添加\n点击替换 · 可删除',
      PhotoSlotState.error => '$englishLabel · 需要处理\n照片异常 · 重新选择',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          supportingText,
          style: TextStyle(
            color: supportingColor,
            fontSize: 11,
            height: 15 / 11,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _PhotoSlotStatus extends StatelessWidget {
  const _PhotoSlotStatus({required this.state});

  final PhotoSlotState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PhotoSlotState.empty => _StatusCircle(
        size: 38,
        backgroundColor: AppColors.accentPrimary,
        borderColor: AppColors.accentPrimary,
        icon: Icons.add_rounded,
        iconColor: AppColors.background,
        iconSize: 22,
      ),
      PhotoSlotState.filled => Opacity(
        opacity: 0.86,
        child: _StatusCircle(
          size: 38,
          backgroundColor: AppColors.success,
          borderColor: AppColors.success,
          icon: Icons.check_rounded,
          iconColor: AppColors.background,
          iconSize: 20,
        ),
      ),
      PhotoSlotState.error => _StatusCircle(
        size: 38,
        backgroundColor: AppColors.error.withValues(alpha: 0.12),
        borderColor: AppColors.error.withValues(alpha: 0.5),
        icon: Icons.priority_high_rounded,
        iconColor: AppColors.error,
        iconSize: 20,
      ),
    };
  }
}

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({
    required this.size,
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.iconSize,
  });

  final double size;
  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

class _PhotoSlotBorderPainter extends CustomPainter {
  const _PhotoSlotBorderPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final RRect border = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(AppRadii.medium - 0.5),
    );

    if (!dashed) {
      canvas.drawRRect(border, paint);
      return;
    }

    const double dashLength = 8;
    const double gapLength = 6;
    final Path borderPath = Path()..addRRect(border);
    for (final PathMetric metric in borderPath.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = (distance + dashLength).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PhotoSlotBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}
