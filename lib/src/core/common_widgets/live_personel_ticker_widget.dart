import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket/websocket_service.dart';

class LivePersonelTickerWidget extends ConsumerStatefulWidget {
  final String title;
  final int? alertCount;
  final String? alertLabel;
  final VoidCallback? onRefresh;

  const LivePersonelTickerWidget({
    super.key,
    this.title = 'CANLI SERVİS AKIŞI',
    this.alertCount,
    this.alertLabel,
    this.onRefresh,
  });

  @override
  ConsumerState<LivePersonelTickerWidget> createState() => _LivePersonelTickerWidgetState();
}

class _LivePersonelTickerWidgetState extends ConsumerState<LivePersonelTickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(wsStateProvider).valueOrNull ?? WebSocketConnectionState.disconnected;
    final isConnected = wsState == WebSocketConnectionState.authenticated ||
        wsState == WebSocketConnectionState.subscribed;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    final statusColor = isConnected
        ? const Color(0xFF10B981)
        : (wsState == WebSocketConnectionState.connecting ||
                wsState == WebSocketConnectionState.authenticating
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444));

    final statusText = isConnected
        ? 'CANLI AKIŞ AKTİF'
        : (wsState == WebSocketConnectionState.connecting ||
                wsState == WebSocketConnectionState.authenticating
            ? 'BAĞLANIYOR...'
            : 'ÇEVRİMDIŞI (YENİDEN DENE)');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Glowing Pulse Dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: _pulseAnimation.value),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),

          // Label and Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusText,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.alertCount != null && widget.alertCount! > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, size: 14, color: Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${widget.alertCount} ${widget.alertLabel ?? 'bekleyen çağrı'}!',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Action / Re-sync button
          IconButton(
            icon: const Icon(Icons.sync_rounded, size: 18),
            color: isDark ? Colors.white70 : const Color(0xFF475569),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Anlık Yenile',
            onPressed: () {
              try {
                HapticFeedback.mediumImpact();
              } catch (_) {}
              ref.read(webSocketServiceProvider).connect();
              widget.onRefresh?.call();
            },
          ),
        ],
      ),
    );
  }
}
