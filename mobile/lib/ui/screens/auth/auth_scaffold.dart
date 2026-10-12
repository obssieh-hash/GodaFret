import 'package:flutter/material.dart';

import '../../widgets/brand.dart';

/// Écran d'authentification épuré : fond uni, barre du haut minimale.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.onBack, this.trailing});

  final Widget child;
  final VoidCallback? onBack;

  /// Action en haut à droite (ex. réglages du serveur).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  if (onBack != null)
                    IconButton(onPressed: onBack, tooltip: 'Retour', icon: const Icon(Icons.arrow_back_rounded)),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Logo des écrans de connexion : l'icône de l'application.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => AppIconImage(size: size);
}

/// Grand titre aligné à gauche + sous-titre (style des écrans d'accueil).
class AuthTitle extends StatelessWidget {
  const AuthTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
          ],
        ],
      );
}
