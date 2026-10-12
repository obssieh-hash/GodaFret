import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/theme.dart';

/// Icône de l'application (carré arrondi bleu nuit, pont doré, « PAY »).
class AppIconImage extends StatelessWidget {
  const AppIconImage({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.26),
      boxShadow: [
        BoxShadow(color: AppColors.gold.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 10)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.asset(Brand.appIcon, fit: BoxFit.cover, semanticLabel: Brand.app),
  );
}

/// Logo horizontal « [pont] golden bridge PAY ».
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.onDark = false, this.size = 18, this.showPay = true});

  final bool onDark;
  final double size;
  final bool showPay;

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? Colors.white : AppColors.navy;
    return Semantics(
      label: Brand.app,
      excludeSemantics: true,
      // Se réduit sur les petits écrans plutôt que de déborder.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(Brand.logoMark, height: size * 1.05),
            SizedBox(width: size * 0.4),
            Text(
              'golden bridge',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: size,
                letterSpacing: -size * 0.04,
                height: 1,
              ),
            ),
            if (showPay) ...[SizedBox(width: size * 0.35), PayPill(size: size * 0.62)],
          ],
        ),
      ),
    );
  }
}

class PayPill extends StatelessWidget {
  const PayPill({super.key, this.size = 12});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(size * 0.75, size * 0.18, size * 0.6, size * 0.18),
    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(size * 2)),
    child: Text(
      'PAY',
      style: TextStyle(
        color: AppColors.navy,
        fontWeight: FontWeight.w800,
        fontSize: size,
        letterSpacing: size * 0.18,
        height: 1.2,
      ),
    ),
  );
}
