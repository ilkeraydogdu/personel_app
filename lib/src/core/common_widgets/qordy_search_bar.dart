import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class QordySearchBar extends StatelessWidget {
  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const QordySearchBar({
    super.key,
    this.hintText = 'Ara...',
    this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final iconColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    Widget buildField(bool hasText) {
      return TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyMedium.copyWith(color: textColor),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(Icons.search, color: iconColor),
          suffixIcon: hasText
              ? IconButton(
                  icon: Icon(Icons.clear, color: iconColor),
                  onPressed: () {
                    controller?.clear();
                    if (onChanged != null) onChanged!('');
                  },
                )
              : null,
        ),
      );
    }

    if (controller != null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller!,
        builder: (context, value, _) => buildField(value.text.isNotEmpty),
      );
    }
    return buildField(false);
  }
}
