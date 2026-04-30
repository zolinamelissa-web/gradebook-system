import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CurvedBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;
  final double? curveHeight;
  final double? bottomSpacing;

  const CurvedBackground({
    super.key,
    required this.child,
    this.colors,
    this.curveHeight,
    this.bottomSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final responsiveCurveHeight =
        curveHeight ?? _getResponsiveCurveHeight(screenWidth);
    final responsiveBottomSpacing =
        bottomSpacing ?? _getResponsiveBottomSpacing(screenHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: responsiveBottomSpacing),
      child: Stack(
        children: [
          CustomPaint(
            painter: _CurvePainter(colors: colors ?? AppTheme.curveColors),
            child: SizedBox(
              width: double.infinity,
              height: responsiveCurveHeight,
            ),
          ),
          child,
        ],
      ),
    );
  }

  double _getResponsiveCurveHeight(double width) {
    if (width >= 1200) return 280;
    if (width >= 900) return 250;
    if (width >= 600) return 230;
    return 220;
  }

  double _getResponsiveBottomSpacing(double height) {
    if (height < 700) return 50;
    if (height < 800) return 70;
    if (height < 900) return 90;
    return 110;
  }
}

class _CurvePainter extends CustomPainter {
  final List<Color> colors;

  _CurvePainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors[0], colors.length > 1 ? colors[1] : colors[0]],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path1 = Path();
    path1.moveTo(0, 0);
    path1.lineTo(size.width, 0);
    path1.lineTo(size.width, size.height * 0.75);
    path1.quadraticBezierTo(
      size.width * 0.75,
      size.height * 1.1,
      size.width * 0.5,
      size.height * 0.88,
    );
    path1.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.65,
      0,
      size.height * 0.85,
    );
    path1.close();
    canvas.drawPath(path1, paint1);

    final paint2 = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, size.height * 0.4);
    path2.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.2,
      size.width * 0.6,
      size.height * 0.5,
    );
    path2.quadraticBezierTo(
      size.width * 0.8,
      size.height * 0.7,
      size.width,
      size.height * 0.5,
    );
    path2.lineTo(size.width, 0);
    path2.lineTo(0, 0);
    path2.close();
    canvas.drawPath(path2, paint2);

    final paint3 = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    final path3 = Path();
    path3.moveTo(0, size.height * 0.6);
    path3.quadraticBezierTo(
      size.width * 0.4,
      size.height * 0.3,
      size.width * 0.7,
      size.height * 0.65,
    );
    path3.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.8,
      size.width,
      size.height * 0.6,
    );
    path3.lineTo(size.width, 0);
    path3.lineTo(0, 0);
    path3.close();
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FullCurvedBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;

  const FullCurvedBackground({super.key, required this.child, this.colors});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _FullCurvePainter(colors: colors ?? AppTheme.curveColors),
        ),
        child,
      ],
    );
  }
}

class _FullCurvePainter extends CustomPainter {
  final List<Color> colors;

  _FullCurvePainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors[0],
          colors.length > 1 ? colors[1] : colors[0],
          colors.length > 2 ? colors[2] : colors[0],
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final wave1 = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final wavePath1 = Path();
    wavePath1.moveTo(0, size.height * 0.3);
    wavePath1.cubicTo(
      size.width * 0.25,
      size.height * 0.15,
      size.width * 0.5,
      size.height * 0.45,
      size.width * 0.75,
      size.height * 0.25,
    );
    wavePath1.cubicTo(
      size.width * 0.9,
      size.height * 0.1,
      size.width,
      size.height * 0.3,
      size.width,
      size.height * 0.3,
    );
    wavePath1.lineTo(size.width, 0);
    wavePath1.lineTo(0, 0);
    wavePath1.close();
    canvas.drawPath(wavePath1, wave1);

    final wave2 = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    final wavePath2 = Path();
    wavePath2.moveTo(0, size.height * 0.85);
    wavePath2.cubicTo(
      size.width * 0.3,
      size.height * 0.7,
      size.width * 0.6,
      size.height * 0.95,
      size.width,
      size.height * 0.75,
    );
    wavePath2.lineTo(size.width, size.height);
    wavePath2.lineTo(0, size.height);
    wavePath2.close();
    canvas.drawPath(wavePath2, wave2);

    final circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      size.width * 0.25,
      circlePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.75),
      size.width * 0.18,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
