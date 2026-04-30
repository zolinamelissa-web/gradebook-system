import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _WebGoogleSignInButton(
        onPressed: widget.onPressed,
        isLoading: widget.isLoading,
      );
    } else {
      return _MobileGoogleSignInButton(
        onPressed: widget.onPressed,
        isLoading: widget.isLoading,
      );
    }
  }
}

class _WebGoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const _WebGoogleSignInButton({
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Google "G" logo
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF4285F4),
                        ),
                        child: const Center(
                          child: Text(
                            'G',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Sign in with Google',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MobileGoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const _MobileGoogleSignInButton({
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const _GoogleLogo(size: 18),
      label: Text(
        isLoading ? 'Signing in...' : 'Sign in with Google',
        style: const TextStyle(fontSize: 16),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        side: BorderSide(color: Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  final double size;

  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw "G" shape with Google colors
    // Red part
    paint.color = const Color(0xFFEA4335);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - radius * 0.3, center.dy - radius * 0.7)
        ..lineTo(center.dx + radius * 0.1, center.dy - radius * 0.7)
        ..lineTo(center.dx + radius * 0.3, center.dy - radius * 0.5)
        ..lineTo(center.dx + radius * 0.3, center.dy - radius * 0.1)
        ..lineTo(center.dx + radius * 0.1, center.dy + radius * 0.1)
        ..lineTo(center.dx - radius * 0.3, center.dy + radius * 0.1)
        ..lineTo(center.dx - radius * 0.5, center.dy - radius * 0.3)
        ..lineTo(center.dx - radius * 0.5, center.dy - radius * 0.7)
        ..close(),
      paint,
    );

    // Blue part
    paint.color = const Color(0xFF4285F4);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + radius * 0.3, center.dy - radius * 0.5)
        ..lineTo(center.dx + radius * 0.7, center.dy - radius * 0.5)
        ..lineTo(center.dx + radius * 0.7, center.dy + radius * 0.1)
        ..lineTo(center.dx + radius * 0.3, center.dy + radius * 0.1)
        ..close(),
      paint,
    );

    // Green part
    paint.color = const Color(0xFF34A853);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + radius * 0.1, center.dy + radius * 0.1)
        ..lineTo(center.dx + radius * 0.3, center.dy + radius * 0.1)
        ..lineTo(center.dx + radius * 0.7, center.dy + radius * 0.5)
        ..lineTo(center.dx - radius * 0.3, center.dy + radius * 0.5)
        ..lineTo(center.dx - radius * 0.5, center.dy + radius * 0.3)
        ..lineTo(center.dx - radius * 0.3, center.dy + radius * 0.1)
        ..close(),
      paint,
    );

    // Yellow part
    paint.color = const Color(0xFFFBBC05);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - radius * 0.5, center.dy - radius * 0.3)
        ..lineTo(center.dx - radius * 0.3, center.dy - radius * 0.3)
        ..lineTo(center.dx - radius * 0.3, center.dy + radius * 0.1)
        ..lineTo(center.dx - radius * 0.5, center.dy + radius * 0.3)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
