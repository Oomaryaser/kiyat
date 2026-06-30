import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class KiyatLogo extends StatelessWidget {
  const KiyatLogo({
    super.key,
    this.size = 44,
    this.showWordmark = true,
  });

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.navy;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _KiyatMarkPainter()),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'كيات',
                style: TextStyle(
                  color: textColor,
                  fontSize: size * 0.44,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'KIYAT',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: size * 0.18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _KiyatMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 120;
    final scaleY = size.height / 120;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final navy = Paint()..color = AppColors.navy;
    final green = Paint()..color = AppColors.primary;
    final white = Paint()..color = Colors.white;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 120, 120),
        const Radius.circular(24),
      ),
      navy,
    );

    final mark = Path()
      ..moveTo(21, 72)
      ..lineTo(59, 72)
      ..lineTo(43, 90)
      ..lineTo(21, 90)
      ..lineTo(37, 72)
      ..close()
      ..moveTo(24, 48)
      ..lineTo(58, 48)
      ..lineTo(44, 66)
      ..lineTo(22, 66)
      ..close()
      ..moveTo(66, 30)
      ..lineTo(96, 30)
      ..lineTo(75, 53)
      ..lineTo(98, 53)
      ..lineTo(70, 84)
      ..lineTo(41, 84)
      ..close();
    canvas.drawPath(mark, white);

    final chevron = Path()
      ..moveTo(83, 46)
      ..lineTo(105, 60)
      ..lineTo(83, 74)
      ..lineTo(91, 60)
      ..close();
    canvas.drawPath(chevron, green);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
