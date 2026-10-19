import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/app_lock_service.dart';
import '../theme/theme_provider.dart';

/// Unified Staff Operations Menu Sheet
/// Opens across all operational dashboards (Waiter, Kitchen, Prep, POS)
/// when tapping the 3-line hamburger menu button.
Future<void> showStaffMenuModal({
  required BuildContext context,
  required WidgetRef ref,
  required String currentScreen, // 'waiter' | 'kitchen' | 'prep' | 'pos'
  VoidCallback? onRefresh,
  String? refreshLabel,
  String? refreshSubtitle,
}) {
  HapticFeedback.mediumImpact();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StaffMenuModalContent(
        parentContext: context,
        currentScreen: currentScreen,
        onRefresh: onRefresh,
        refreshLabel: refreshLabel,
        refreshSubtitle: refreshSubtitle,
      );
    },
  );
}

class StaffMenuModalContent extends ConsumerStatefulWidget {
  final BuildContext parentContext;
  final String currentScreen;
  final VoidCallback? onRefresh;
  final String? refreshLabel;
  final String? refreshSubtitle;

  const StaffMenuModalContent({
    super.key,
    required this.parentContext,
    required this.currentScreen,
    this.onRefresh,
    this.refreshLabel,
    this.refreshSubtitle,
  });

  @override
  ConsumerState<StaffMenuModalContent> createState() => _StaffMenuModalContentState();
}

class _StaffMenuModalContentState extends ConsumerState<StaffMenuModalContent> {
  Future<void> _handleLogout(bool isDark) async {
    final isIOS = !kIsWeb && Platform.isIOS;
    bool? confirmed;

    if (isIOS) {
      confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogCtx) => CupertinoAlertDialog(
          title: const Text('Oturumu Kapat'),
          content: const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              'Personel oturumunu kapatmak istediğinize emin misiniz? Canlı sipariş ve masa verileri sistemde korunacaktır.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Vazgeç'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Çıkış Yap'),
            ),
          ],
        ),
      );
    } else {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 10),
              Text('Oturumu Kapat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text(
            'Personel oturumunu kapatmak istediğinize emin misiniz? Canlı sipariş ve masa verileri sistemde korunacaktır.',
            style: TextStyle(fontSize: 14),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Vazgeç', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (confirmed == true && mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      if (widget.parentContext.mounted) {
        widget.parentContext.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = !kIsWeb && Platform.isIOS;
    final auth = ref.watch(authProvider);
    final isLockEnabled = ref.watch(appLockEnabledProvider);
    final themePref = ref.watch(themeModeProvider.notifier).preference;

    final staffName = (auth.userName != null && auth.userName!.isNotEmpty) ? auth.userName! : 'Personel';
    final initialLetter = staffName.isNotEmpty ? staffName[0].toUpperCase() : 'P';

    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final cardBorder = isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0);

    // Module theme styling
    Color primaryAccent;
    String moduleTitle;
    switch (widget.currentScreen) {
      case 'kitchen':
        primaryAccent = const Color(0xFF0D9488);
        moduleTitle = 'Mutfak KDS Paneli';
        break;
      case 'prep':
        primaryAccent = const Color(0xFFEC4899);
        moduleTitle = 'Bar & Hazırlık Paneli';
        break;
      case 'pos':
        primaryAccent = const Color(0xFF10B981);
        moduleTitle = 'Kasa & POS Terminali';
        break;
      case 'waiter':
      default:
        primaryAccent = const Color(0xFF6366F1);
        moduleTitle = 'Garson Terminali';
        break;
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.18),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // iOS style drag handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 14),

            // Top Header: Staff Profile & Module Identity
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryAccent, primaryAccent.withValues(alpha: 0.75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryAccent.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initialLetter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staffName,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '$moduleTitle • Çevrimiçi',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded, size: 18, color: textSecondary),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1),

            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. OPERATIONAL REFRESH TILE
                    Text(
                      'OPERASYONEL SENKRONİZASYON',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onRefresh?.call();
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text('Canlı veriler anında senkronize edildi.'),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: primaryAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.refresh_rounded, color: primaryAccent, size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.refreshLabel ?? 'Verileri Canlı Yenile',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.refreshSubtitle ?? 'Masa ve siparişleri sunucuyla eşitle',
                                        style: TextStyle(color: textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: textSecondary, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 2. SECURITY & BIOMETRIC LOCK
                    Text(
                      'GÜVENLİK & KORUMA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: (isLockEnabled ? const Color(0xFF10B981) : Colors.grey).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isLockEnabled
                                  ? (isIOS ? CupertinoIcons.viewfinder : Icons.fingerprint_rounded)
                                  : Icons.lock_open_rounded,
                              color: isLockEnabled ? const Color(0xFF10B981) : textSecondary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isIOS ? 'Face ID / Cihaz Kilidi' : 'Biyometrik / Cihaz Kilidi',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isLockEnabled
                                      ? 'Uygulama arka plana geçtiğinde kilitlenir'
                                      : 'Kilit koruması kapalı (doğrudan açılır)',
                                  style: TextStyle(color: textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: isLockEnabled,
                            activeThumbColor: const Color(0xFF10B981),
                            activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.5),
                            onChanged: (val) async {
                              HapticFeedback.selectionClick();
                              await ref.read(appLockEnabledProvider.notifier).toggle();
                              if (!mounted) return;
                              setState(() {});
                              final updated = ref.read(appLockEnabledProvider);
                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    updated
                                        ? (isIOS ? 'Face ID / Cihaz kilidi koruması açıldı.' : 'Cihaz kilidi koruması açıldı.')
                                        : 'Cihaz kilidi koruması kapatıldı.',
                                  ),
                                  backgroundColor: updated ? const Color(0xFF10B981) : Colors.grey.shade700,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 3. THEME PREFERENCES
                    Text(
                      'ARAYÜZ VE TEMA MODU',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildThemeOption(
                          title: 'Koyu',
                          icon: Icons.dark_mode_rounded,
                          isSelected: themePref == AppThemePreference.dark,
                          isDark: isDark,
                          primaryAccent: primaryAccent,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(themeModeProvider.notifier).setPreference(AppThemePreference.dark);
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildThemeOption(
                          title: 'Açık',
                          icon: Icons.light_mode_rounded,
                          isSelected: themePref == AppThemePreference.light,
                          isDark: isDark,
                          primaryAccent: primaryAccent,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(themeModeProvider.notifier).setPreference(AppThemePreference.light);
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildThemeOption(
                          title: 'Sistem',
                          icon: Icons.settings_suggest_rounded,
                          isSelected: themePref == AppThemePreference.system,
                          isDark: isDark,
                          primaryAccent: primaryAccent,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(themeModeProvider.notifier).setPreference(AppThemePreference.system);
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildThemeOption(
                          title: 'Gece',
                          icon: Icons.access_time_rounded,
                          isSelected: themePref == AppThemePreference.scheduled,
                          isDark: isDark,
                          primaryAccent: primaryAccent,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(themeModeProvider.notifier).setPreference(AppThemePreference.scheduled);
                            setState(() {});
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 4. LOGOUT BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => _handleLogout(isDark),
                        icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                        label: const Text(
                          'Personel Oturumunu Kapat',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required Color primaryAccent,
    required Color textPrimary,
    required Color textSecondary,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryAccent.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? primaryAccent : (isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? primaryAccent : textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? primaryAccent : textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
