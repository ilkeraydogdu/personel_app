import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/common_widgets/qordy_button.dart';
import '../../../core/common_widgets/qordy_card.dart';
import '../../../core/common_widgets/qordy_text_field.dart';

class RegisterStep4Screen extends StatelessWidget {
  const RegisterStep4Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ADIM 4/4', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    Text('Güvenlik Kurulumu', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(value: 1.0, backgroundColor: AppColors.surface, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                const SizedBox(height: 32),
                const Text('Şifre Belirleme', style: AppTextStyles.heading1),
                const SizedBox(height: 8),
                Text(
                  'Son adım olarak yönetici hesabınız için güçlü bir şifre tanımlayın.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                QordyCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Yeni Şifre', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 8),
                      const QordyTextField(hintText: '••••••••', prefixIcon: Icons.lock_outline, obscureText: true),
                      const SizedBox(height: 24),
                      const Text('Şifre Tekrar', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 8),
                      const QordyTextField(hintText: '••••••••', prefixIcon: Icons.lock_outline, obscureText: true),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Şifre Gücü:', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                          Text('GÜÇLÜ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(width: 4),
                          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(width: 4),
                          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(width: 4),
                          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: AppColors.surfaceDark, borderRadius: BorderRadius.circular(2)))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildChecklist('En az 8 karakter'),
                      _buildChecklist('Büyük ve küçük harf'),
                      _buildChecklist('Rakam içermeli'),
                      _buildChecklist('Özel karakter içermeli'),
                      const SizedBox(height: 32),
                      QordyButton(text: 'Kayıt Ol', onPressed: () => context.go('/')),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChecklist(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 16),
          const SizedBox(width: 8),
          Text(text, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
