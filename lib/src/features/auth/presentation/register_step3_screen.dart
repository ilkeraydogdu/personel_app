import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/common_widgets/qordy_button.dart';
import '../../../core/common_widgets/qordy_card.dart';
import '../../../core/common_widgets/qordy_otp_input.dart';

class RegisterStep3Screen extends StatelessWidget {
  const RegisterStep3Screen({super.key});

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
                    Text('ADIM 3/4', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    Text('Mobil Doğrulama', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(value: 0.75, backgroundColor: AppColors.surface, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                const SizedBox(height: 32),
                const Text('Telefon Doğrulama', style: AppTextStyles.heading1),
                const SizedBox(height: 8),
                Text(
                  'Sipariş bildirimleri ve SMS kimlik doğrulama için cep telefonunuzu onaylayın.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                QordyCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Telefon Numarası', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 8),
                      TextField(
                        keyboardType: TextInputType.phone,
                        style: AppTextStyles.bodyLarge,
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🇹🇷 +90', style: AppTextStyles.bodyLarge),
                                const SizedBox(width: 8),
                                Container(width: 1, height: 24, color: AppColors.border),
                              ],
                            ),
                          ),
                          hintText: '555 123 4567',
                          hintStyle: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.surfaceDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SMS Doğrulama Kodu', style: AppTextStyles.bodyMedium),
                          Text('SMS KODU GÖNDERİLDİ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      QordyOtpInput(length: 6, onCompleted: (v) {}),
                      const SizedBox(height: 32),
                      QordyButton(text: 'Doğrula ve Devam Et', onPressed: () => context.push('/register/step4')),
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
}
