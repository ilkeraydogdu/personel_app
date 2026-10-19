import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../localization/app_localizations.dart';
import '../theme/theme_provider.dart';
import '../theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/shift_provider.dart';

class PersonelAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? extraActions;

  const PersonelAppBar({
    super.key,
    required this.title,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shiftStatus = ref.watch(shiftProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (shiftStatus.isSilentMode || !shiftStatus.isOnShift)
            GestureDetector(
              onTap: () {
                _showShiftInfoDialog(context, ref, shiftStatus);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.nightlight_round, size: 11, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      l10n.t('silent_mode_active'),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (extraActions != null) ...extraActions!,
        // 3-Dots Quick Settings Menu
        PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: 'Menü',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          onSelected: (value) async {
            if (value == 'theme') {
              ref.read(themeModeProvider.notifier).toggleTheme();
            } else if (value == 'shift') {
              _showShiftInfoDialog(context, ref, shiftStatus);
            } else if (value == 'logout') {
              _confirmLogout(context, ref);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'theme',
              child: Row(
                children: [
                  Icon(
                    isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    size: 20,
                    color: isDark ? Colors.amber : Colors.indigo,
                  ),
                  const SizedBox(width: 10),
                  Text(isDark ? 'Açık Tema' : 'Koyu Tema'),
                ],
              ),
            ),
            if (shiftStatus.isSilentMode || !shiftStatus.isOnShift)
              const PopupMenuItem(
                value: 'shift',
                child: Row(
                  children: [
                    Icon(Icons.nightlight_round, size: 20, color: Colors.amber),
                    SizedBox(width: 10),
                    Text('Vardiya Durumu'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 20, color: Colors.redAccent),
                  SizedBox(width: 10),
                  Text('Çıkış Yap', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }


  void _showShiftInfoDialog(BuildContext context, WidgetRef ref, ShiftStatus shift) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.nightlight_round, color: Colors.amber),
            const SizedBox(width: 8),
            Text(l10n.t('shift_status')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shift.isOnShift ? l10n.t('on_shift') : l10n.t('off_shift'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: shift.isOnShift ? Colors.green : Colors.amber.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.t('silent_mode_desc')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(shiftProvider.notifier).toggleSilentMode();
              Navigator.pop(ctx);
            },
            child: Text(shift.isSilentMode ? 'Sessiz Modu Kapat' : 'Sessiz Modu Aç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('confirm')),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Oturumu Kapat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Personel oturumunu kapatmak istediğinize emin misiniz? Devam eden açık işlemleriniz sistemde güvende kalacaktır.',
          style: TextStyle(fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
