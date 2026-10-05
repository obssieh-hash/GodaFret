import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Fond sombre dégradé commun aux écrans d'authentification.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.onBack, this.trailing});

  final Widget child;
  final VoidCallback? onBack;

  /// Action en haut à droite (ex. réglages du serveur).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.nightGradient),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: _Glow(color: AppColors.violet.withValues(alpha: 0.45), size: 320),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _Glow(color: AppColors.teal.withValues(alpha: 0.25), size: 340),
            ),
            SafeArea(
              child: Column(
                children: [
                  if (onBack != null || trailing != null)
                    Row(
                      children: [
                        if (onBack != null)
                          IconButton(
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          ),
                        const Spacer(),
                        ?trailing,
                      ],
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: size * 0.5),
      );
}

/// Décoration de champ adaptée au fond sombre.
InputDecoration darkField(String label, IconData icon, {Widget? suffix}) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: Colors.white60),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF8B85FF), width: 1.6),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFF8FA3)),
    );
