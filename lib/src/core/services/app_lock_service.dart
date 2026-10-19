import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/secure_storage.dart';
import 'biometric_service.dart';
import '../providers/auth_provider.dart';

const _storage = SecureStorage.instance;
const _kAppLockEnabledKey = 'personel_app_lock_enabled';

class AppLockNotifier extends StateNotifier<bool> {
  AppLockNotifier() : super(false) {
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final val = await _storage.read(key: _kAppLockEnabledKey);
      if (val != null) {
        state = val == 'true';
      } else {
        state = false;
      }
    } catch (e) {
      debugPrint('[AppLockNotifier] Failed to load lock state: $e');
      state = false;
    }
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    state = enabled;
    try {
      await _storage.write(key: _kAppLockEnabledKey, value: enabled ? 'true' : 'false');
    } catch (e) {
      debugPrint('[AppLockNotifier] Failed to persist lock state: $e');
    }
  }

  Future<void> toggle() async {
    await setAppLockEnabled(!state);
  }
}

final appLockEnabledProvider = StateNotifierProvider<AppLockNotifier, bool>((ref) {
  return AppLockNotifier();
});

/// Tracks whether the app is currently locked on screen
final isScreenLockedProvider = StateProvider<bool>((ref) => false);

/// App Lock Manager that observes lifecycle safely without looping
class AppLockManager with WidgetsBindingObserver {
  final WidgetRef _ref;
  static bool _isCurrentlyPrompting = false;
  DateTime? _pausedAt;

  AppLockManager(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }

  Future<void> _handleAppResume() async {
    if (_isCurrentlyPrompting) return;

    final isAuth = _ref.read(authProvider).isAuthenticated;
    final isLockEnabled = _ref.read(appLockEnabledProvider);

    if (!isAuth || !isLockEnabled) return;

    // Lock if app was in background for more than 3 seconds
    if (_pausedAt != null) {
      final diff = DateTime.now().difference(_pausedAt!).inSeconds;
      if (diff < 3) return;
    } else {
      return;
    }

    _ref.read(isScreenLockedProvider.notifier).state = true;
    await triggerUnlockPrompt();
  }

  Future<bool> triggerUnlockPrompt() async {
    if (_isCurrentlyPrompting) return false;
    _isCurrentlyPrompting = true;

    try {
      final isIOS = !kIsWeb && Platform.isIOS;
      final success = await BiometricService.authenticate(
        reason: isIOS
            ? 'Qordy Personel oturumunuza devam etmek için Face ID veya cihaz parolanızı doğrulayın'
            : 'Qordy Personel oturumunuza devam etmek için cihaz kilidinizi doğrulayın',
      );

      if (success) {
        HapticFeedback.lightImpact();
        _ref.read(isScreenLockedProvider.notifier).state = false;
        _pausedAt = null;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[AppLockManager] Biometric auth error: $e');
      return false;
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        _isCurrentlyPrompting = false;
      });
    }
  }
}

/// Cinematic iOS Frosted Glass & Luxury Obsidian App Lock Screen Overlay Wrapper
class AppLockOverlayWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const AppLockOverlayWrapper({super.key, required this.child});

  @override
  ConsumerState<AppLockOverlayWrapper> createState() => _AppLockOverlayWrapperState();
}

class _AppLockOverlayWrapperState extends ConsumerState<AppLockOverlayWrapper> {
  AppLockManager? _lockManager;

  @override
  void initState() {
    super.initState();
    _lockManager = AppLockManager(ref);
  }

  @override
  void dispose() {
    _lockManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = ref.watch(isScreenLockedProvider);
    final isAuth = ref.watch(authProvider).isAuthenticated;
    final isIOS = !kIsWeb && Platform.isIOS;

    return Stack(
      children: [
        widget.child,
        if (isLocked && isAuth)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF070B14).withValues(alpha: 0.88),
                    ),
                    child: Stack(
                      children: [
                        // Ambient emerald and indigo background glow
                        Positioned(
                          top: -60,
                          left: -40,
                          child: Container(
                            width: 320,
                            height: 320,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF10B981).withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -80,
                          right: -50,
                          child: Container(
                            width: 340,
                            height: 340,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                            ),
                          ),
                        ),

                        // Main Glassmorphic Lock Card
                        SafeArea(
                          child: Center(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 36,
                                      offset: const Offset(0, 18),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Glowing Shield / Face ID Icon
                                    Container(
                                      width: 92,
                                      height: 92,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF10B981).withValues(alpha: 0.14),
                                        border: Border.all(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.48),
                                          width: 1.8,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.30),
                                            blurRadius: 28,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Icon(
                                          isIOS ? CupertinoIcons.lock_shield_fill : Icons.lock_rounded,
                                          size: 44,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // Brand Title
                                    const Text(
                                      'QORDY GÜVENLİK',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    Text(
                                      isIOS ? 'Face ID & Terminal Kilidi' : 'Cihaz Kilidi Aktif',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 23,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    Text(
                                      isIOS
                                          ? 'Personel terminalinize güvenli şekilde devam etmek için lütfen Face ID, Touch ID veya iPhone parolanızı doğrulayın.'
                                          : 'Personel oturumunuza güvenli şekilde devam etmek için lütfen cihaz kilidinizi (parmak izi veya telefon şifrenizi) doğrulayın.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 13.5,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 32),

                                    // Primary Unlock Button
                                    SizedBox(
                                      width: double.infinity,
                                      height: 54,
                                      child: ElevatedButton.icon(
                                        onPressed: () async {
                                          HapticFeedback.selectionClick();
                                          await _lockManager?.triggerUnlockPrompt();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                                        ),
                                        icon: Icon(
                                          isIOS ? CupertinoIcons.viewfinder : Icons.fingerprint_rounded,
                                          size: 22,
                                        ),
                                        label: Text(
                                          isIOS ? 'Face ID ile Kilidi Aç' : 'Kilidi Aç',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Secondary Action: Logout
                                    TextButton.icon(
                                      onPressed: () async {
                                        HapticFeedback.lightImpact();
                                        ref.read(isScreenLockedProvider.notifier).state = false;
                                        await ref.read(authProvider.notifier).logout();
                                      },
                                      icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFEF4444)),
                                      label: const Text(
                                        'Farklı Personel ile Giriş / Çıkış Yap',
                                        style: TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
