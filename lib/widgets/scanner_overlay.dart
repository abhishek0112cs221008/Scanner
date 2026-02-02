import 'package:flutter/material.dart';

class ScannerOverlay extends StatefulWidget {
  final Rect scanWindow;

  const ScannerOverlay({super.key, required this.scanWindow});

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background with a hole (the scan window)
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: widget.scanWindow.width,
                  height: widget.scanWindow.height,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Corners and scanning line
        Align(
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: ScannerOverlayPainter(
                  scanWindow: widget.scanWindow,
                  animationValue: _animation.value,
                ),
                size: Size(widget.scanWindow.width, widget.scanWindow.height),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final double animationValue;

  ScannerOverlayPainter({
    required this.scanWindow,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final path = Path();
    double cornerLength = 30;
    double radius = 20;

    // Top Left Corner
    path.moveTo(0, cornerLength);
    path.lineTo(0, radius);
    path.arcToPoint(Offset(radius, 0), radius: Radius.circular(radius));
    path.lineTo(cornerLength, 0);

    // Top Right Corner
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - radius, 0);
    path.arcToPoint(
      Offset(size.width, radius),
      radius: Radius.circular(radius),
    );
    path.lineTo(size.width, cornerLength);

    // Bottom Right Corner
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height - radius);
    path.arcToPoint(
      Offset(size.width - radius, size.height),
      radius: Radius.circular(radius),
    );
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom Left Corner
    path.moveTo(cornerLength, size.height);
    path.lineTo(radius, size.height);
    path.arcToPoint(
      Offset(0, size.height - radius),
      radius: Radius.circular(radius),
    );
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);

    // Scanning line animation with Premium Glow
    final lineY = animationValue * size.height;

    // Outer Glow
    final glowPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.3)
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawLine(
      Offset(10, lineY),
      Offset(size.width - 10, lineY),
      glowPaint,
    );

    // Main Vibrant Line
    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.blueAccent.withOpacity(0.01),
          Colors.blueAccent.withOpacity(0.8),
          Colors.white,
          Colors.blueAccent.withOpacity(0.8),
          Colors.blueAccent.withOpacity(0.01),
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, lineY - 2, size.width, 4))
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(5, lineY), Offset(size.width - 5, lineY), linePaint);
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
