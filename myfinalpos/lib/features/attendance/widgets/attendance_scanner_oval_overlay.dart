import 'package:flutter/material.dart';

/// Shared face-guide oval used on web, Android, and iOS scanners.
class AttendanceScannerOvalOverlay extends StatelessWidget {
  const AttendanceScannerOvalOverlay({super.key});

  static const double widthFactor = 0.44;
  static const double heightFactor = 0.78;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: AttendanceScannerOvalPainter());
  }
}

class AttendanceScannerOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hole = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * AttendanceScannerOvalOverlay.widthFactor,
      height: size.height * AttendanceScannerOvalOverlay.heightFactor,
    );

    final dim = Paint()..color = const Color(0x59111827);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dim);

    canvas.drawOval(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xD9FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
