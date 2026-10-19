import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/secure_storage.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/theme/theme_provider.dart';

const _storage = SecureStorage.instance;
const _kCachedBusinessName = 'personel_cached_business_name';
const _kCachedBusinessLogo = 'personel_cached_business_logo';
const _kCachedBusinessSubdomain = 'personel_cached_business_subdomain';
const _kCachedBusinessNumber = 'personel_cached_business_number';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _businessCodeController = TextEditingController();
  Timer? _businessDebounce;

  // Current Step: 1 = İşletme Kodu Girişi, 2 = İşletme Onaylandı & PIN Girişi
  int _currentStep = 1;
  bool _isLoadingBusiness = false;
  String? _businessError;
  String _pin = '';
  bool _isLoggingIn = false;

  Map<String, dynamic>? _businessInfo;

  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _businessCodeController.addListener(_onBusinessCodeChanged);
    _initSavedBusinessAndBiometrics();
  }

  void _onBusinessCodeChanged() {
    final text = _businessCodeController.text.trim();
    _businessDebounce?.cancel();

    if (_businessError != null) {
      setState(() => _businessError = null);
    } else {
      setState(() {});
    }

    if (text.length == 6 && _currentStep == 1 && !_isLoadingBusiness) {
      _validateBusinessCode();
    }
  }

  @override
  void dispose() {
    _businessDebounce?.cancel();
    _businessCodeController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _initSavedBusinessAndBiometrics() async {
    try {
      final savedSub = await _storage.read(key: _kCachedBusinessSubdomain);
      final savedName = await _storage.read(key: _kCachedBusinessName);
      final savedLogo = await _storage.read(key: _kCachedBusinessLogo);
      final savedNum = await _storage.read(key: _kCachedBusinessNumber);

      if (savedSub != null && savedSub.isNotEmpty) {
        setState(() {
          _businessInfo = {
            'subdomain': savedSub,
            'business_number': savedNum ?? '',
            'name': savedName ?? savedSub,
            'logo': savedLogo,
          };
          _currentStep = 2;
        });
      }

      final canBio = await BiometricService.isBiometricAvailable();
      final creds = await BiometricService.getSavedCredentials();
      final didLogout = await BiometricService.didExplicitLogout();

      // Otonom Cihaz Kilidi / Biyometrik Giriş: 
      // SADECE kullanıcı bilinçli olarak "Çıkış Yap" dememişse otonom tetikle.
      // Eğer kullanıcı Çıkış Yap dediyse, zorla biometric açılmaz; dilerse tuş takımındaki parmak izi butonuna dokunur.
      if (!didLogout && canBio && creds != null && creds['pin'] != null && _currentStep == 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isLoggingIn) {
            _tryBiometricLogin(creds['subdomain'] ?? '', creds['pin']!);
          }
        });
      }
    } catch (e) {
      debugPrint('[LoginScreen] Biometric init error: $e');
    }
  }

  Future<void> _tryBiometricLogin(String subdomain, String pin) async {
    if (_isLoggingIn) return;
    final isIOS = !kIsWeb && Platform.isIOS;
    final authenticated = await BiometricService.authenticate(
      reason: isIOS
          ? 'Qordy Personel hesabınıza Face ID veya iPhone parolanızla hızlıca giriş yapın'
          : 'Qordy Personel hesabınıza telefon kilidinizle hızlıca giriş yapın',
    );
    if (authenticated && mounted) {
      HapticFeedback.mediumImpact();
      _executeLogin(pin: pin, subdomain: subdomain);
    }
  }

  Future<void> _triggerBiometricManual() async {
    if (_isLoggingIn) return;
    HapticFeedback.selectionClick();
    try {
      final creds = await BiometricService.getSavedCredentials();
      if (creds != null && creds['pin'] != null && creds['pin']!.isNotEmpty) {
        final subdomain = creds['subdomain'] ?? _businessInfo?['subdomain'] ?? '';
        await _tryBiometricLogin(subdomain, creds['pin']!);
      } else {
        if (mounted) {
          final isIOS = !kIsWeb && Platform.isIOS;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isIOS
                    ? 'Face ID / Touch ID ile giriş yapabilmek için lütfen önce PIN kodunuzla bir kez giriş yapın.'
                    : 'Biyometrik / cihaz kilidiyle giriş yapabilmek için lütfen önce PIN kodunuzla bir kez giriş yapın.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFF6366F1),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[LoginScreen] Manual biometric error: $e');
    }
  }

  // ─── Step 1: Validate Business Code / Subdomain ───────────
  Future<void> _validateBusinessCode() async {
    final code = _businessCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _businessError = 'Lütfen işletme kodunu girin');
      return;
    }

    setState(() {
      _isLoadingBusiness = true;
      _businessError = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post('/validate-subdomain', data: {
        'subdomain': code,
        'business_number': code,
      });

      final result = response;
      final dataObj = result['data'] is Map ? result['data'] as Map : null;
      if (result['success'] == true && dataObj?['valid'] == true) {
        final biz = dataObj!['business'] as Map;
        final sub = biz['subdomain']?.toString() ?? code;
        final bizNumber = biz['business_number']?.toString() ?? code;
        final name = biz['name']?.toString() ?? 'İşletme';
        final logo = biz['logo']?.toString();

        await _storage.write(key: _kCachedBusinessSubdomain, value: sub);
        await _storage.write(key: _kCachedBusinessName, value: name);
        await _storage.write(key: _kCachedBusinessNumber, value: bizNumber);
        if (logo != null) await _storage.write(key: _kCachedBusinessLogo, value: logo);

        if (mounted) {
          setState(() {
            _businessInfo = {
              'subdomain': sub,
              'business_number': bizNumber,
              'name': name,
              'logo': logo,
            };
            _currentStep = 2;
            _pin = '';
          });
        }
      } else {
        setState(() => _businessError = 'Geçersiz işletme kodu');
      }
    } on DioException catch (e) {
      String msg = 'İşletme bulunamadı veya sunucuya ulaşılamadı';
      if (e.response?.data != null && e.response?.data is Map) {
        msg = e.response?.data['error'] ?? msg;
      }
      setState(() => _businessError = msg);
    } catch (e) {
      debugPrint('[LoginScreen] Business validation error: $e');
      setState(() => _businessError = 'Doğrulama sırasında bir hata oluştu');
    } finally {
      if (mounted) {
        setState(() => _isLoadingBusiness = false);
      }
    }
  }

  void _changeBusiness() async {
    await _storage.delete(key: _kCachedBusinessSubdomain);
    await _storage.delete(key: _kCachedBusinessName);
    await _storage.delete(key: _kCachedBusinessLogo);
    await _storage.delete(key: _kCachedBusinessNumber);
    await BiometricService.clearBiometricCredentials();

    if (!mounted) return;
    setState(() {
      _currentStep = 1;
      _businessInfo = null;
      _pin = '';
      _businessError = null;
      _businessCodeController.clear();
    });
  }

  // ─── Step 2: PIN Pad Input ────────────────────────────────
  void _onKeypadTap(String value) {
    if (_isLoggingIn) return;

    HapticFeedback.lightImpact();

    if (value == 'clear') {
      setState(() => _pin = '');
    } else if (value == 'backspace') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    } else {
      if (_pin.length < 4) {
        final newPin = _pin + value;
        setState(() => _pin = newPin);

        if (newPin.length == 4) {
          _attemptStaffLogin(newPin);
        }
      }
    }
  }

  Future<void> _attemptStaffLogin(String pin) async {
    final sub = _businessInfo?['subdomain'] ?? '';
    if (sub.isEmpty) return;
    _executeLogin(pin: pin, subdomain: sub);
  }

  Future<void> _executeLogin({required String pin, required String subdomain}) async {
    setState(() => _isLoggingIn = true);

    final success = await ref.read(authProvider.notifier).loginWithPin(
      pin: pin,
      subdomain: subdomain,
    );

    if (success && mounted) {
      await BiometricService.setExplicitLogout(false);
      await BiometricService.saveCredentialsForBiometric(
        subdomain: subdomain,
        pin: pin,
      );
    } else if (mounted) {
      setState(() {
        _isLoggingIn = false;
        _pin = '';
      });

      _shakeController.forward(from: 0.0);
      HapticFeedback.heavyImpact();

      final err = ref.read(authProvider).error ?? 'Giriş başarısız. Lütfen PIN kodunuzu kontrol edin.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              // Top Bar: Unified executive compact header
              if (_currentStep == 2) ...[
                Builder(
                  builder: (context) {
                    final bizName = _businessInfo?['name'] ?? 'İşletme';
                    final bizLogo = _businessInfo?['logo']?.toString();
                    final bizSub = _businessInfo?['subdomain'] ?? '';
                    final bizNum = (_businessInfo?['business_number']?.toString().isNotEmpty ?? false)
                        ? _businessInfo!['business_number'].toString()
                        : bizSub;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Business Logo (Compact 34x34) with online indicator
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: (AppConfig.assetUrl(bizLogo) ?? '').isNotEmpty
                                      ? Image.network(
                                          AppConfig.assetUrl(bizLogo)!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.storefront_rounded, color: Color(0xFF6366F1), size: 18),
                                        )
                                      : const Icon(Icons.storefront_rounded, color: Color(0xFF6366F1), size: 18),
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cardBg, width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),

                          // Business Name & Number
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  bizName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '#$bizNum',
                                  style: const TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Değiştir Action Chip
                          InkWell(
                            onTap: _changeBusiness,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFF6366F1)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Değiştir',
                                    style: TextStyle(
                                      color: Color(0xFF6366F1),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Quick Theme Toggle
                          IconButton(
                            icon: Icon(
                              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                              size: 18,
                              color: textSecondary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 36),
                    Text(
                      'PERSONEL PORTAL',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        size: 20,
                        color: textSecondary,
                      ),
                      onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Animated Transition between Step 1 and Step 2
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 350),
                crossFadeState: _currentStep == 1 ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                firstChild: _buildStep1BusinessCode(cardBg, textPrimary, textSecondary, isDark),
                secondChild: _buildStep2PinEntry(cardBg, textPrimary, textSecondary, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STEP 1: İşletme Kodu Girişi
  // ══════════════════════════════════════════════════════════════
  Widget _buildStep1BusinessCode(Color cardBg, Color textPrimary, Color textSecondary, bool isDark) {
    return Column(
      children: [
        // Qordy Brand Logo matching business app
        Container(
          width: 72,
          height: 72,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Personel Girişi',
          style: TextStyle(
            color: textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Mesaiye başlamak ve panellere erişmek için 6 haneli işletme kodunuzu girin.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),

        // Business Code Input Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'İşletme Kodu',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              // TextField
              TextField(
                controller: _businessCodeController,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _validateBusinessCode(),
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                ),
                decoration: InputDecoration(
                  hintText: 'Örn: 296466',
                  hintStyle: TextStyle(
                    color: textSecondary.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
                  prefixIcon: const Icon(Icons.pin_outlined, color: Color(0xFF6366F1)),
                  suffixIcon: _isLoadingBusiness
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF6366F1)),
                          ),
                        )
                      : (_businessCodeController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _businessCodeController.clear()),
                            )
                          : null),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                  ),
                ),
              ),

              if (_businessError != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _businessError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '6 haneli kod tamamlandığında sistem otonom olarak bağlanır.',
                      style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              if (_businessCodeController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingBusiness ? null : _validateBusinessCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('İşletmeye Bağlan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STEP 2: İşletme Profili & PIN Girişi
  // ══════════════════════════════════════════════════════════════
  Widget _buildStep2PinEntry(Color cardBg, Color textPrimary, Color textSecondary, bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 8),

        Text(
          'Personel PIN Kodu',
          style: TextStyle(
            color: textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Giriş yapmak için 4 haneli şifrenizi girin',
          style: TextStyle(color: textSecondary, fontSize: 13),
        ),

        const SizedBox(height: 24),

        // ─── PIN Indicator Dots (with Shake Animation on error) ───
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final offset = _mathSinOffset(_shakeController.value);
            return Transform.translate(
              offset: Offset(offset, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? const Color(0xFF6366F1)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                      border: Border.all(
                        color: isFilled
                            ? const Color(0xFF6366F1)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        width: 2,
                      ),
                      boxShadow: isFilled
                          ? [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
            );
          },
        ),

        if (_isLoggingIn) ...[
          const SizedBox(height: 24),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: Color(0xFF6366F1), strokeWidth: 2.5),
          ),
        ],

        const SizedBox(height: 32),

        // ─── Numeric Keypad (Figma 2026 UI) ───
        _buildNumericKeypad(cardBg, textPrimary, textSecondary, isDark),
      ],
    );
  }

  double _mathSinOffset(double progress) {
    return math.sin(progress * 6 * math.pi) * 12 * (1.0 - progress);
  }

  /// Modern numeric keypad for staff PIN entry
  Widget _buildNumericKeypad(Color cardBg, Color textPrimary, Color textSecondary, bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _keypadButton('1', textPrimary, cardBg, isDark),
              _keypadButton('2', textPrimary, cardBg, isDark),
              _keypadButton('3', textPrimary, cardBg, isDark),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _keypadButton('4', textPrimary, cardBg, isDark),
              _keypadButton('5', textPrimary, cardBg, isDark),
              _keypadButton('6', textPrimary, cardBg, isDark),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _keypadButton('7', textPrimary, cardBg, isDark),
              _keypadButton('8', textPrimary, cardBg, isDark),
              _keypadButton('9', textPrimary, cardBg, isDark),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Clear Button or Biometrics / Face ID Button
              _pin.isNotEmpty
                  ? _keypadIconButton(
                      Icons.clear_rounded,
                      textSecondary,
                      () => _onKeypadTap('clear'),
                      cardBg,
                      isDark,
                    )
                  : _keypadIconButton(
                      (!kIsWeb && Platform.isIOS)
                          ? CupertinoIcons.viewfinder
                          : Icons.fingerprint_rounded,
                      const Color(0xFF6366F1),
                      _triggerBiometricManual,
                      cardBg,
                      isDark,
                    ),

              _keypadButton('0', textPrimary, cardBg, isDark),

              // Backspace Button
              _keypadIconButton(
                (!kIsWeb && Platform.isIOS)
                    ? CupertinoIcons.delete_left
                    : Icons.backspace_outlined,
                textSecondary,
                () => _onKeypadTap('backspace'),
                cardBg,
                isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keypadButton(String text, Color textPrimary, Color cardBg, bool isDark) {
    return InkWell(
      onTap: () => _onKeypadTap(text),
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: cardBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypadIconButton(IconData icon, Color iconColor, VoidCallback onTap, Color cardBg, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: cardBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: 26),
        ),
      ),
    );
  }
}
