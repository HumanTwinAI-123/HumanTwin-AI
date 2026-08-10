import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.width = 350,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.medium)),
        boxShadow: onPressed == null
            ? const <BoxShadow>[]
            : const <BoxShadow>[
                BoxShadow(color: Color(0x2986D7FF), blurRadius: 18),
              ],
      ),
      child: SizedBox(
        width: width,
        height: 56,
        child: FilledButton(
          onPressed: onPressed,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith<Color>((
              Set<WidgetState> states,
            ) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.surface2;
              }
              if (states.contains(WidgetState.pressed)) {
                return AppColors.accentPressed;
              }
              return AppColors.accentPrimary;
            }),
            foregroundColor: WidgetStateProperty.resolveWith<Color>(
              (Set<WidgetState> states) => states.contains(WidgetState.disabled)
                  ? AppColors.textTertiary
                  : AppColors.background,
            ),
            shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(width: 20),
              Expanded(child: Text(label, textAlign: TextAlign.center)),
              const Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
