import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'src/core/routing/app_router.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/theme_provider.dart';
import 'src/core/localization/app_localizations.dart';
import 'src/core/localization/locale_provider.dart';
import 'src/core/services/app_lifecycle_coordinator.dart';
import 'src/core/services/app_lock_service.dart';
import 'src/core/services/notification_service.dart';
import 'src/core/services/widget_sync_service.dart';

/// Platform-adaptive scroll physics across all terminals (Waiter, KDS, POS, Bar)
class QordyAdaptiveScrollBehavior extends MaterialScrollBehavior {
  const QordyAdaptiveScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]),
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0E1A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: QordyPersonelApp(),
    ),
  );

  // Initialize Native HomeWidget & Notification Channels after first frame renders
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await PersonelWidgetSyncService.initialize();
    await PersonelNotificationService().initialize();
    await PersonelNotificationService().requestPermissionsIfNeeded();
  });
}

void unawaited(Future<void> future) {}

class QordyPersonelApp extends ConsumerWidget {
  const QordyPersonelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appLifecycleCoordinatorProvider);
    final goRouter = ref.watch(appRouterProvider);
    final currentLocale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Qordy Personel',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const QordyAdaptiveScrollBehavior(),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: currentLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  statusBarBrightness: Brightness.dark,
                  statusBarIconBrightness: Brightness.light,
                  systemNavigationBarColor: const Color(0xFF0A0E1A),
                  systemNavigationBarIconBrightness: Brightness.light,
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  statusBarBrightness: Brightness.light,
                  statusBarIconBrightness: Brightness.dark,
                  systemNavigationBarColor: const Color(0xFFF8FAFC),
                  systemNavigationBarIconBrightness: Brightness.dark,
                ),
          child: AppLockOverlayWrapper(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      routerConfig: goRouter,
    );
  }
}
