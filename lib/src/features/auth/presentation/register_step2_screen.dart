import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/common_widgets/qordy_button.dart';
import '../../../core/common_widgets/qordy_card.dart';
import '../../../core/common_widgets/qordy_text_field.dart';
import '../../../core/common_widgets/qordy_otp_input.dart';

class RegisterStep2Screen extends StatelessWidget {
  const RegisterStep2Screen({super.key});

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
                    Text('ADIM 2/4', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    Text('E-posta Onay', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(value: 0.50, backgroundColor: AppColors.surface, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                const SizedBox(height: 32),
                const Text('E-posta Doğrulama', style: AppTextStyles.heading1),
                const SizedBox(height: 8),
                Text(
                  'Hesap güvenliğinizi sağlamak için doğrulama kodunu girin.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                QordyCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Kayıtlı E-posta Adresi', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 8),
                      const QordyTextField(hintText: 'ornek@email.com', prefixIcon: Icons.email_outlined),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Doğrulama Kodu (E-Posta)', style: AppTextStyles.bodyMedium),
                          Text('KOD GÖNDERİLDİ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      QordyOtpInput(length: 6, onCompleted: (v) {}),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Kod elinize ulaşmadı mı? ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                          Text('Tekrar Gönder (45s)', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 32),
                      QordyButton(text: 'Doğrula ve Devam Et', onPressed: () => context.push('/register/step3')),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Text('Geri dön ve Bilgileri Düzenle', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
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
