import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../../core/network/api_client.dart';

class AiVoiceOrderSheet extends ConsumerStatefulWidget {
  final String? initialTableId;
  final String? initialTableName;
  final VoidCallback? onOrderPlaced;

  const AiVoiceOrderSheet({
    super.key,
    this.initialTableId,
    this.initialTableName,
    this.onOrderPlaced,
  });

  @override
  ConsumerState<AiVoiceOrderSheet> createState() => _AiVoiceOrderSheetState();
}

class _AiVoiceOrderSheetState extends ConsumerState<AiVoiceOrderSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _speechInitialized = false;
  bool _isAnalyzing = false;
  bool _isConfirming = false;
  bool _isConfirmed = false;
  String? _errorMessage;

  // Parsed AI order data
  String? _resolvedTableId;
  String? _resolvedTableName;
  List<Map<String, dynamic>> _parsedItems = [];
  List<String> _unrecognized = [];
  double _totalAmount = 0.0;
  bool _hasParsedPreview = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _resolvedTableId = widget.initialTableId;
    _resolvedTableName = widget.initialTableName;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initSpeechRecognizer();
  }

  void _setListeningState(bool listening) {
    if (_isListening == listening) return;
    _isListening = listening;
    if (listening) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initSpeechRecognizer() async {
    try {
      _speechInitialized = await _speech.initialize(
        onError: (err) {
          if (mounted) {
            setState(() {
              _setListeningState(false);
              if (err.errorMsg.isNotEmpty && err.errorMsg != 'error_no_match') {
                _errorMessage = 'Ses algılama hatası: ${err.errorMsg}';
              }
            });
          }
        },
        onStatus: (status) {
          if (mounted) {
            if (status == 'done' || status == 'notListening') {
              setState(() => _setListeningState(false));
              if (_textController.text.trim().isNotEmpty && !_hasParsedPreview) {
                _parseWithAi();
              }
            }
          }
        },
      );
      if (mounted) setState(() {});
    } catch (_) {
      _speechInitialized = false;
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _setListeningState(false));
        if (_textController.text.trim().isNotEmpty) {
          _parseWithAi();
        }
      }
      return;
    }

    if (!_speechInitialized) {
      await _initSpeechRecognizer();
    }

    if (!_speechInitialized) {
      setState(() {
        _errorMessage = 'Sesli komut için mikrofon servisi hazır değil. Lütfen elle yazarak deneyin.';
      });
      return;
    }

    setState(() {
      _setListeningState(true);
      _errorMessage = null;
      _hasParsedPreview = false;
      _parsedItems = [];
    });

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
          localeId: 'tr_TR',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
        ),
        onResult: (result) {
          if (mounted) {
            setState(() {
              _textController.text = result.recognizedWords;
            });
            if (result.finalResult) {
              setState(() => _setListeningState(false));
              _parseWithAi();
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _setListeningState(false);
          _errorMessage = 'Ses dinleme başlatılamadı: $e';
        });
      }
    }
  }

  Future<void> _parseWithAi() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final result = await api.post('/waiter/ai-order', data: {
        'text': text,
        'table_id': _resolvedTableId,
        'confirm': false,
      });

      if (result['success'] == true) {
        final data = Map<String, dynamic>.from(result['data'] ?? {});
        setState(() {
          _hasParsedPreview = true;
          if (data['table_id'] != null && (data['table_id'].toString().isNotEmpty)) {
            _resolvedTableId = data['table_id'].toString();
          }
          if (data['table_name'] != null && (data['table_name'].toString().isNotEmpty)) {
            _resolvedTableName = data['table_name'].toString();
          }
          _parsedItems = (data['items'] as List? ?? [])
              .map((it) => Map<String, dynamic>.from(it as Map))
              .toList();
          _unrecognized = (data['unrecognized'] as List? ?? [])
              .map((it) => it.toString())
              .toList();
          _totalAmount = double.tryParse('${data['total_amount'] ?? 0}') ?? 0.0;
        });
      } else {
        setState(() {
          _errorMessage = result['error']?.toString() ?? 'Sipariş ayrıştırılamadı.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e is ApiException
            ? e.message
            : 'Yapay zekâ servisine bağlanılamadı. Lütfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _confirmAndSendOrder() async {
    if (_resolvedTableId == null || _resolvedTableId!.isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen geçerli bir masa seçin veya belirtin.';
      });
      return;
    }

    if (_parsedItems.isEmpty) {
      setState(() {
        _errorMessage = 'Sipariş listesinde henüz onaylanacak ürün yok.';
      });
      return;
    }

    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final result = await api.post('/waiter/ai-order', data: {
        'text': _textController.text.trim(),
        'table_id': _resolvedTableId,
        'confirm': true,
        'items': _parsedItems,
      });

      if (result['success'] == true) {
        setState(() {
          _isConfirmed = true;
        });
        widget.onOrderPlaced?.call();
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else {
        setState(() {
          _errorMessage = result['error']?.toString() ?? 'Sipariş onaylanamadı.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e is ApiException ? e.message : 'Sipariş iletilirken hata oluştu.';
      });
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  void _updateItemQuantity(int index, int delta) {
    setState(() {
      final current = int.tryParse('${_parsedItems[index]['quantity'] ?? 1}') ?? 1;
      final newQty = current + delta;
      if (newQty <= 0) {
        _parsedItems.removeAt(index);
      } else {
        _parsedItems[index]['quantity'] = newQty;
        final price = double.tryParse('${_parsedItems[index]['price'] ?? 0}') ?? 0.0;
        _parsedItems[index]['line_total'] = price * newQty;
      }
      _recalculateTotal();
    });
  }

  void _recalculateTotal() {
    double sum = 0.0;
    for (final it in _parsedItems) {
      final price = double.tryParse('${it['price'] ?? 0}') ?? 0.0;
      final qty = int.tryParse('${it['quantity'] ?? 1}') ?? 1;
      sum += (price * qty);
    }
    _totalAmount = sum;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF131B2E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Sesli Hızlı Sipariş',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                'AI CANLI',
                                style: TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.initialTableName != null
                              ? '${widget.initialTableName} için konuşarak sipariş verin'
                              : 'Masayı ve ürünleri konuşarak söyleyin',
                          style: TextStyle(color: textSecColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textSecColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Microphone Pulsing Voice Capsule (Apple/Awwwards grade)
              Center(
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isListening
                                ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                                : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: (_isListening ? const Color(0xFFEF4444) : const Color(0xFF6366F1))
                                  .withValues(alpha: _isListening ? 0.45 : 0.25),
                              blurRadius: _isListening ? 18 : 8,
                              spreadRadius: _isListening ? 2 : 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isListening ? 'Dinleniyor... (Durdur)' : 'Konuşmaya Başla',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_isListening) ...[
                              const SizedBox(width: 8),
                              _buildListeningWaveform(),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Center(
                child: Text(
                  _isListening
                      ? 'Dinleniyor... (Örn: "Masa 14 iki burger domates olmasın bir kola")'
                      : 'Konuşmak için butona dokunun veya durdurun',
                  style: TextStyle(
                    color: _isListening ? const Color(0xFFEF4444) : textSecColor,
                    fontSize: 12,
                    fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Transcribed Speech Text Field
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isListening ? const Color(0xFF6366F1) : borderColor,
                    width: _isListening ? 1.5 : 1.0,
                  ),
                ),
                child: TextField(
                  controller: _textController,
                  maxLines: 3,
                  style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
                  decoration: InputDecoration(
                    hintText: 'Garson sesli komutu buraya dökülür veya elle düzenlenebilir...',
                    hintStyle: TextStyle(color: textSecColor.withValues(alpha: 0.7), fontSize: 13),
                    contentPadding: const EdgeInsets.all(14),
                    border: InputBorder.none,
                    suffixIcon: _textController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18, color: textSecColor),
                            onPressed: () {
                              setState(() {
                                _textController.clear();
                                _hasParsedPreview = false;
                                _parsedItems = [];
                                _unrecognized = [];
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) {
                    if (_hasParsedPreview) {
                      setState(() => _hasParsedPreview = false);
                    }
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Action Bar: "AI ile Çözümle" button
              if (!_hasParsedPreview && !_isConfirmed)
                ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _parseWithAi,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _isAnalyzing ? 'Yapay Zekâ Siparişi Çözümlüyor...' : 'Siparişi Çözümle & Önizle',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),

              // Error Banner
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Success Confirmed Banner
              if (_isConfirmed) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sipariş Mutfağa İletildi!',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_resolvedTableName için ${_parsedItems.length} kalem sipariş hazırlandı.',
                              style: TextStyle(color: textSecColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Parsed Order Preview Card
              if (_hasParsedPreview && !_isConfirmed) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Target Table Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.table_restaurant, color: Color(0xFF10B981), size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      _resolvedTableName ?? 'Masa Belirtilmedi',
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '₺${_totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Items List
                      if (_parsedItems.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Eşleşen ürün bulunamadı. Lütfen sesli komutu tekrarlayın.',
                              style: TextStyle(color: textSecColor, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _parsedItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final it = _parsedItems[idx];
                            final name = it['name']?.toString() ?? '';
                            final price = double.tryParse('${it['price'] ?? 0}') ?? 0.0;
                            final qty = int.tryParse('${it['quantity'] ?? 1}') ?? 1;
                            final excluded = (it['excluded_ingredients'] as List? ?? [])
                                .map((e) => e.toString())
                                .toList();
                            final extras = (it['selected_extras'] as List? ?? [])
                                .map((e) => e.toString())
                                .toList();

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '₺${(price * qty).toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Modifiers (Excluded & Extras)
                                  if (excluded.isNotEmpty || extras.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final ex in excluded)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.remove_circle_outline, size: 11, color: Colors.redAccent),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$ex olmasın',
                                                  style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        for (final ext in extras)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.add_circle_outline, size: 11, color: Colors.green),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '+ $ext',
                                                  style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],

                                  const SizedBox(height: 8),

                                  // Stepper Controls
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      InkWell(
                                        onTap: () => _updateItemQuantity(idx, -1),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(Icons.remove, size: 16, color: textColor),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text(
                                          '$qty',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _updateItemQuantity(idx, 1),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.add, size: 16, color: Color(0xFF6366F1)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      if (_unrecognized.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Anlaşılamayanlar: ${_unrecognized.join(", ")}',
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Giant One-Tap Confirm Button
                      ElevatedButton.icon(
                        onPressed: _isConfirming || _parsedItems.isEmpty ? null : _confirmAndSendOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        icon: _isConfirming
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, size: 20),
                        label: Text(
                          _isConfirming
                              ? 'Mutfağa İletiliyor...'
                              : 'Siparişi Onayla & Mutfağa Gönder',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListeningWaveform() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final height = 6.0 + (index % 2 == 0 ? 8.0 * _pulseAnimation.value : 4.0 * (2.0 - _pulseAnimation.value));
        return Container(
          width: 2.5,
          height: height.clamp(4.0, 16.0),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

