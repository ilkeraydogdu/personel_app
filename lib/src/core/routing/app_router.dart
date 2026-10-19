import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/waiter/presentation/waiter_dashboard.dart';
import '../../features/waiter/presentation/table_details_screen.dart';
import '../../features/kitchen/presentation/kitchen_dashboard.dart';
import '../../features/pos/presentation/pos_dashboard.dart';
import '../../features/preparation/presentation/prep_dashboard.dart';
import '../providers/auth_provider.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStateNotifier = ValueNotifier<AuthState>(ref.read(authProvider));

  ref.listen<AuthState>(
    authProvider,
    (_, next) => authStateNotifier.value = next,
  );

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authStateNotifier,
    redirect: (context, state) {
      final isAuthenticated = authStateNotifier.value.isAuthenticated;
      final role = (authStateNotifier.value.userRole ?? 'waiter').toLowerCase();
      final currentPath = state.uri.path;
      final isGoingToLogin = currentPath == '/';

      if (!isAuthenticated) {
        return isGoingToLogin ? null : '/';
      }

      // Determine home route for role
      String roleHome = '/waiter';
      if (role == 'pos' || role == 'cashier') {
        roleHome = '/pos';
      } else if (role == 'kitchen') {
        roleHome = '/kitchen';
      } else if (role == 'preparation' || role == 'prep') {
        roleHome = '/prep';
      }

      if (isGoingToLogin) {
        return roleHome;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/waiter',
        builder: (context, state) => const WaiterDashboard(),
        routes: [
          GoRoute(
            path: 'table/:id',
            builder: (context, state) {
              final tableId = state.pathParameters['id']!;
              final tableName = state.extra is String ? state.extra as String : null;
              return TableDetailsScreen(tableId: tableId, tableName: tableName);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/kitchen',
        builder: (context, state) => const KitchenDashboard(),
      ),
      GoRoute(
        path: '/pos',
        builder: (context, state) => const PosDashboard(),
      ),
      GoRoute(
        path: '/prep',
        builder: (context, state) => const PrepDashboard(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text('Sayfa bulunamadı', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Girişe Dön'),
            ),
          ],
        ),
      ),
    ),
  );

  ref.onDispose(() {
    authStateNotifier.dispose();
    router.dispose();
  });

  return router;
});
