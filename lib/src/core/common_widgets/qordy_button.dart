import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum QordyButtonType { primary, secondary, outline, text }

class QordyButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final QordyButtonType type;
  final bool isLoading;
  final Widget? icon;

  const QordyButton({
    super.key,
    required this.text,
    this.onPressed,
    this.type = QordyButtonType.primary,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    switch (type) {
      case QordyButtonType.primary:
        return _buildPrimaryButton(disabled, isDark);
      case QordyButtonType.secondary:
        return _buildSecondaryButton(disabled, isDark);
      case QordyButtonType.outline:
        return _buildOutlineButton(disabled, isDark);
      case QordyButtonType.text:
        return _buildTextButton(disabled);
    }
  }

  Widget _buildPrimaryButton(bool disabled, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: disabled ? null : AppColors.primaryGradient,
        color: disabled ? (isDark ? AppColors.surfaceDark : AppColors.lightSurfaceSecondary) : null,
        borderRadius: BorderRadius.circular(32),
        boxShadow: disabled ? [] : [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            alignment: Alignment.center,
            child: _buildContent(disabled ? (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary) : Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(bool disabled, bool isDark) {
    return _baseButton(
      disabled: disabled,
      bgColor: isDark ? AppColors.surfaceDark : AppColors.lightSurfaceSecondary,
      textColor: AppColors.primary,
    );
  }

  Widget _buildOutlineButton(bool disabled, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
        borderRadius: BorderRadius.circular(32),
      ),
      child: _baseButton(
        disabled: disabled,
        bgColor: Colors.transparent,
        textColor: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
      ),
    );
  }

  Widget _buildTextButton(bool disabled) {
    return _baseButton(
      disabled: disabled,
      bgColor: Colors.transparent,
      textColor: AppColors.primary,
      noPadding: true,
    );
  }

  Widget _baseButton({
    required bool disabled,
    required Color bgColor,
    required Color textColor,
    bool noPadding = false,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          padding: noPadding
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          alignment: Alignment.center,
          child: _buildContent(textColor),
        ),
      ),
    );
  }

  Widget _buildContent(Color textColor) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(textColor),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          icon!,
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: AppTextStyles.bodyLarge.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
