import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A custom animated 60 FPS cooking pan widget.
/// Renders a frying pan with bouncing sizzling ingredients,
/// pulsing heat glow underneath, and rising steam trails.
class SizzlingPanAnimation extends StatefulWidget {
  final double size;
  final bool isAnimated;

  const SizzlingPanAnimation({
    super.key,
    this.size = 56,
    this.isAnimated = true,
  });

  @override
  State<SizzlingPanAnimation> createState() => _SizzlingPanAnimationState();
}

class _SizzlingPanAnimationState extends State<SizzlingPanAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isAnimated) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SizzlingPanAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isAnimated && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _SizzlingPanPainter(progress: _controller.value),
        );
      },
    );
  }
}

class _SizzlingPanPainter extends CustomPainter {
  final double progress;

  _SizzlingPanPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final panCenter = Offset(w * 0.44, h * 0.62);
    final panRadius = w * 0.32;

    // 1. Under-pan Heat Glow (Orange / Amber pulsating radial gradient)
    final heatPulse = 0.7 + 0.3 * math.sin(progress * 2 * math.pi);
    final heatPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.deepOrangeAccent.withValues(alpha: 0.35 * heatPulse),
          Colors.amber.withValues(alpha: 0.15 * heatPulse),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(panCenter.dx, panCenter.dy + panRadius * 0.4),
        radius: panRadius * 1.3,
      ));

    canvas.drawCircle(
      Offset(panCenter.dx, panCenter.dy + panRadius * 0.4),
      panRadius * 1.3,
      heatPaint,
    );

    // 2. Rising Steam Trails (3 Sinusoidal vertical curves)
    final steamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final steamOffset = (i * 0.33);
      final steamProg = (progress + steamOffset) % 1.0;
      final steamAlpha = (1.0 - steamProg) * 0.85;

      if (steamAlpha > 0.05) {
        steamPaint.color = Colors.white.withValues(alpha: steamAlpha);

        final steamX = panCenter.dx + (i - 1) * (panRadius * 0.55);
        final startY = panCenter.dy - panRadius * 0.2;
        final endY = startY - (h * 0.45 * steamProg);

        final path = Path();
        path.moveTo(steamX, startY);

        final midY = (startY + endY) / 2;
        final wave = math.sin((steamProg * 2 * math.pi) + i) * (w * 0.06);

        path.quadraticBezierTo(
          steamX + wave,
          midY,
          steamX - wave * 0.5,
          endY,
        );

        canvas.drawPath(path, steamPaint);
      }
    }

    // 3. Pan Handle (Extending to bottom-right)
    final handlePaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;

    final handleEnd = Offset(w * 0.94, h * 0.74);
    canvas.drawLine(
      Offset(panCenter.dx + panRadius * 0.85, panCenter.dy + panRadius * 0.25),
      handleEnd,
      handlePaint,
    );

    // Handle grip accent (rubber grip)
    final gripPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(panCenter.dx + panRadius * 1.1, panCenter.dy + panRadius * 0.38),
      handleEnd,
      gripPaint,
    );

    // 4. Pan Outer Rim (Deep dark gunmetal / titanium)
    final panOuterPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(panCenter, panRadius, panOuterPaint);

    // Pan Rim border
    final rimBorderPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04;
    canvas.drawCircle(panCenter, panRadius, rimBorderPaint);

    // 5. Pan Cooking Surface (Slightly darker non-stick interior)
    final interiorRadius = panRadius * 0.82;
    final interiorPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFF0F172A),
          Color(0xFF020617),
        ],
      ).createShader(Rect.fromCircle(center: panCenter, radius: interiorRadius));
    canvas.drawCircle(panCenter, interiorRadius, interiorPaint);

    // 6. Sizzling Food Items (Bouncing Kebap/Burger patties & sizzling dots)
    // Sizzle bobbing motion
    final bounce1 = math.sin(progress * 4 * math.pi) * (h * 0.03);
    final bounce2 = math.cos(progress * 5 * math.pi) * (h * 0.025);

    // Sizzling patty 1 (Golden-brown roasted piece)
    final food1Paint = Paint()..color = const Color(0xFFD97706); // Amber
    final food1Center = Offset(panCenter.dx - interiorRadius * 0.28, panCenter.dy + bounce1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: food1Center, width: interiorRadius * 0.65, height: interiorRadius * 0.38),
        Radius.circular(w * 0.04),
      ),
      food1Paint,
    );

    // Grill marks on patty 1
    final grillMarkPaint = Paint()
      ..color = const Color(0xFF78350F)
      ..strokeWidth = w * 0.025
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(food1Center.dx - interiorRadius * 0.2, food1Center.dy - interiorRadius * 0.08),
      Offset(food1Center.dx - interiorRadius * 0.08, food1Center.dy + interiorRadius * 0.08),
      grillMarkPaint,
    );
    canvas.drawLine(
      Offset(food1Center.dx + interiorRadius * 0.05, food1Center.dy - interiorRadius * 0.08),
      Offset(food1Center.dx + interiorRadius * 0.17, food1Center.dy + interiorRadius * 0.08),
      grillMarkPaint,
    );

    // Sizzling patty 2 / side veggies (Tomato slice / pepper)
    final food2Paint = Paint()..color = const Color(0xFFEF4444); // Tomato red
    final food2Center = Offset(panCenter.dx + interiorRadius * 0.32, panCenter.dy + bounce2);
    canvas.drawCircle(food2Center, interiorRadius * 0.22, food2Paint);

    final veggiePaint = Paint()..color = const Color(0xFF10B981); // Green pepper
    canvas.drawCircle(Offset(panCenter.dx + interiorRadius * 0.1, panCenter.dy - interiorRadius * 0.25), interiorRadius * 0.14, veggiePaint);

    // 7. Micro Sizzle Sparkles (Small golden spark dots jumping out)
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    const randSparks = [
      Offset(-0.2, -0.4),
      Offset(0.3, -0.3),
      Offset(-0.1, 0.3),
      Offset(0.25, 0.2),
    ];

    for (int s = 0; s < randSparks.length; s++) {
      final sparkTime = (progress * 3 + s * 0.25) % 1.0;
      final sparkRadius = (w * 0.025) * (1.0 - sparkTime);
      final sparkX = panCenter.dx + (randSparks[s].dx * interiorRadius) + (math.sin(sparkTime * math.pi) * (w * 0.04));
      final sparkY = panCenter.dy + (randSparks[s].dy * interiorRadius) - (sparkTime * (h * 0.15));

      sparkPaint.color = Colors.amberAccent.withValues(alpha: 1.0 - sparkTime);
      canvas.drawCircle(Offset(sparkX, sparkY), sparkRadius.clamp(0.5, 4.0), sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SizzlingPanPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
