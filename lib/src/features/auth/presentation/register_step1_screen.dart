import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/common_widgets/qordy_button.dart';
import '../../../core/common_widgets/qordy_card.dart';
import '../../../core/common_widgets/qordy_text_field.dart';

class RegisterStep1Screen extends StatelessWidget {
  const RegisterStep1Screen({super.key});

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
                    Text('ADIM 1/4', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    Text('İşletme Profili', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(value: 0.25, backgroundColor: AppColors.surface, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                const SizedBox(height: 32),
                const Text('İşletme Bilgileri', style: AppTextStyles.heading1),
                const SizedBox(height: 8),
                Text(
                  'Profilinizi oluşturun ve işletme bilgilerinizi belirleyin.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                QordyCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ad', style: AppTextStyles.bodyMedium),
                                SizedBox(height: 8),
                                QordyTextField(hintText: 'İlker'),
                              ],
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Soyad', style: AppTextStyles.bodyMedium),
                                SizedBox(height: 8),
                                QordyTextField(hintText: 'Dönmez'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text('İşletme Adı', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 8),
                      const QordyTextField(hintText: 'Qordy Bistro'),
                      const SizedBox(height: 24),
                      const Text('Kısa Bağlantı', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 8),
                      TextField(
                        style: AppTextStyles.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'qordybistro',
                          hintStyle: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                          suffixText: '.qordy.com',
                          suffixStyle: AppTextStyles.bodyLarge.copyWith(color: AppColors.primary),
                          filled: true,
                          fillColor: AppColors.surfaceDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('🔗 Önizleme: qordybistro.qordy.com', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                      const SizedBox(height: 32),
                      QordyButton(text: 'Devam Et', onPressed: () => context.push('/register/step2')),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: GestureDetector(
                    onTap: () => context.canPop() ? context.pop() : context.go('/'),
                    child: Text('Zaten hesabınız var mı? Giriş Yapın', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
