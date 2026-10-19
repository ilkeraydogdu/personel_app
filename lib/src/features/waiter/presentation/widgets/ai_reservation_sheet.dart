import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';

class AiReservationSheet extends ConsumerStatefulWidget {
  const AiReservationSheet({super.key});

  @override
  ConsumerState<AiReservationSheet> createState() => _AiReservationSheetState();
}

class _AiReservationSheetState extends ConsumerState<AiReservationSheet> {
  final TextEditingController _textController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isAnalyzing = false;
  bool _isConfirmed = false;
  String? _errorMessage;
  Map<String, dynamic>? _parsedData;

  bool _isListening = false;
  bool _speechInitialized = false;

  @override
  void initState() {
    super.initState();
    _initSpeechRecognizer();
  }

  @override
  void dispose() {
    _speech.stop();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initSpeechRecognizer() async {
    try {
      _speechInitialized = await _speech.initialize(
        onError: (err) {
          if (mounted) {
            setState(() {
              _isListening = false;
              if (err.errorMsg.isNotEmpty && err.errorMsg != 'error_no_match') {
                _errorMessage = 'Ses algılama hatası: ${err.errorMsg}';
              }
            });
          }
        },
        onStatus: (status) {
          if (mounted) {
            if (status == 'done' || status == 'notListening') {
              setState(() => _isListening = false);
              if (_textController.text.trim().isNotEmpty && _parsedData == null) {
                _processText(confirm: false);
              }
            }
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      _speechInitialized = false;
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
        if (_textController.text.trim().isNotEmpty) {
          _processText(confirm: false);
        }
      }
      return;
    }

    if (!_speechInitialized) {
      await _initSpeechRecognizer();
    }

    if (!_speechInitialized) {
      // Fallback: If device doesn't support Google Speech Services (e.g. some emulators/ROMs)
      setState(() {
        _errorMessage = 'Sesli komut için mikrofon ve konuşma tanıma servisi bulunamadı. Lütfen elle yazın.';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _errorMessage = null;
      _isConfirmed = false;
    });

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
          localeId: 'tr_TR',
          listenFor: const Duration(seconds: 25),
          pauseFor: const Duration(seconds: 3),
        ),
        onResult: (result) {
          if (mounted) {
            setState(() {
              _textController.text = result.recognizedWords;
            });
            if (result.finalResult) {
              setState(() => _isListening = false);
              _handleRecognizedWords(result.recognizedWords);
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _errorMessage = 'Ses kaydı başlatılamadı: $e';
        });
      }
    }
  }

  void _handleRecognizedWords(String words) {
    final lower = words.toLowerCase().trim();
    if (lower.isEmpty) return;

    final shouldAutoConfirm = lower.contains('ekle') ||
        lower.contains('kaydet') ||
        lower.contains('oluştur') ||
        lower.contains('onayla');

    _processText(confirm: shouldAutoConfirm);
  }

  Future<void> _processText({bool confirm = false}) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final result = await api.post('/waiter/ai-reservation', data: {
        'text': text,
        'confirm': confirm,
      });

      if (result['success'] == true) {
        setState(() {
          _parsedData = result['data'] is Map ? Map<String, dynamic>.from(result['data']) : null;
          if (confirm) {
            _isConfirmed = true;
          }
        });
      } else {
        setState(() {
          _errorMessage = result['error']?.toString() ?? 'Rezervasyon ayrıştırılamadı';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e is ApiException
            ? e.message
            : 'Bağlantı hatası veya yapay zekâ servisi yanıt vermedi';
      });
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('ai_reservation'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        l10n.t('ai_reservation_desc'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick suggestion chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildChip('Bu akşam 20:00 2 kişi'),
                  _buildChip('Yarın 19:30 4 kişi Masa 3'),
                  _buildChip('Ahmet Yılmaz bu akşam 4 kişi'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Text input and Voice trigger
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: l10n.t('ai_reservation_desc'),
                      hintStyle: const TextStyle(fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => _processText(confirm: false),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: _isListening ? Colors.redAccent : AppColors.primary,
                  ),
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                  tooltip: l10n.t('ai_speak'),
                  onPressed: _toggleListening,
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_isListening)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dinleniyor... (Bitince otomatik çözümler veya "ekle/kaydet" diyebilirsiniz)',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isAnalyzing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(l10n.t('ai_analyzing'), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),

            // Parsed Preview Card
            if (_parsedData != null && !_isAnalyzing) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.lightSurfaceSecondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _parsedData!['has_conflict'] == true ? Colors.redAccent : Colors.green.shade400,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _parsedData!['has_conflict'] == true ? Icons.warning_amber_rounded : Icons.check_circle,
                          color: _parsedData!['has_conflict'] == true ? Colors.redAccent : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.t('ai_preview_title'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildPreviewRow(l10n.t('guest_name'), _parsedData!['customer_name'] ?? 'Misafir'),
                    _buildPreviewRow(l10n.t('guest_count'), '${_parsedData!['guest_count'] ?? 2} Kişi'),
                    _buildPreviewRow(l10n.t('reservation_date'), '${_parsedData!['reservation_date']}'),
                    _buildPreviewRow(l10n.t('reservation_time'), '${_parsedData!['reservation_time']}'),
                    _buildPreviewRow(l10n.t('assigned_table'), '${_parsedData!['table_name'] ?? 'Masa'}'),
                    if (_parsedData!['has_conflict'] == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('ai_conflict_warning'),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_isConfirmed)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.t('reservation_created'),
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: Text(l10n.t('create_reservation'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () => _processText(confirm: true),
                ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: ActionChip(
        label: Text(text, style: const TextStyle(fontSize: 11)),
        onPressed: () {
          _textController.text = text;
          _processText(confirm: false);
        },
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
