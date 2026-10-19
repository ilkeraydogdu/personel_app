import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

Future<bool> showExitConfirmationDialog(BuildContext context) async {
  return (await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Çıkış'),
      content: const Text('Uygulamadan çıkmak istiyor musunuz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet')),
      ],
    ),
  )) ?? false;
}

class MainShellRoute extends StatefulWidget {
  final Widget child;

  const MainShellRoute({super.key, required this.child});

  @override
  State<MainShellRoute> createState() => _MainShellRouteState();
}

class _MainShellRouteState extends State<MainShellRoute> {
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/orders')) return 1;
    if (location.startsWith('/tables')) return 2;
    if (location.startsWith('/settings')) return 3;
    return -1;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/orders');
        break;
      case 2:
        context.go('/tables');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int selectedIndex = _calculateSelectedIndex(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final String location = GoRouterState.of(context).uri.path;
        
        // Sub-screens that belong to Settings
        final settingsSubRoutes = [
          '/reservations',
          '/notifications',
          '/finance',
          '/personnel',
          '/zones',
          '/receipts',

          '/menu-catalog',
          '/campaigns',
          '/personnels',
          '/personnel-add',
          '/notification-settings',
          '/subscriptions'
        ];
        
        if (location == '/subscription-payment') {
          context.go('/subscription-plans');
          return;
        } else if (location == '/subscription-plans') {
          context.go('/subscriptions');
          return;
        } else if (settingsSubRoutes.contains(location)) {
          // If we are in any settings sub-route and back is pressed, go to settings
          context.go('/settings');
          return;
        }
        
        // Otherwise, show exit dialog
        final shouldExit = await showExitConfirmationDialog(context);
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: widget.child,
      floatingActionButton: MediaQuery.of(context).viewInsets.bottom > 0 ? null : Container(
        height: 64,
        width: 64,
        margin: const EdgeInsets.only(top: 32),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF4F75FF),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F75FF).withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => context.go('/ai-chat'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(
            Icons.auto_awesome,
            size: 32,
            color: Colors.white,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SafeArea(
        child: Container(
          color: const Color(0xFF0D1117),
          child: BottomAppBar(
            color: Colors.transparent,
            elevation: 0,
            child: SizedBox(
              height: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(context, icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Ana Sayfa', isSelected: selectedIndex == 0, onTap: () => _onItemTapped(0, context)),
                  _buildNavItem(context, icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Siparişler', isSelected: selectedIndex == 1, onTap: () => _onItemTapped(1, context)),
                  const SizedBox(width: 48),
                  _buildNavItem(context, icon: Icons.grid_view, selectedIcon: Icons.grid_view, label: 'Masalar', isSelected: selectedIndex == 2, onTap: () => _onItemTapped(2, context)),
                  _buildNavItem(context, icon: Icons.menu, selectedIcon: Icons.menu, label: 'Diğer', isSelected: selectedIndex == 3, onTap: () => _onItemTapped(3, context)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildNavItem(BuildContext context, {required IconData icon, required IconData selectedIcon, required String label, required bool isSelected, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? selectedIcon : icon, color: isSelected ? Colors.white : Colors.white54, size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
