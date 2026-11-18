import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../core/theme.dart';
import '../../../state/session_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';
import '../auth/pin_screens.dart';
import '../home/home_shell.dart';

/// 🔑 Sécurité : MFA/OTP, code PIN, biométrie, verrouillage.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final config = session.config;
    final provider = switch (config.authMode) {
      AuthMode.keycloak => 'Keycloak · royaume « ${config.keycloakRealm} »',
      AuthMode.fineract => 'Apache Fineract (2FA intégré)',
      AuthMode.demo => 'Mode démonstration',
    };

    final device = session.device;
    final checks = <_Check>[
      _Check(Icons.key_rounded, 'Double authentification', session.auth.mfaLabel, true),
      const _Check(Icons.pin_rounded, 'Code PIN à 6 chiffres', 'Codes trop simples refusés, blocage après 5 erreurs', true),
      _Check(
        Icons.fingerprint_rounded,
        'Biométrie',
        session.biometricsEnabled ? 'Activée' : (session.biometricsAvailable ? 'Désactivée' : 'Non disponible'),
        session.biometricsEnabled || !session.biometricsAvailable,
      ),
      _Check(
        Icons.timer_outlined,
        'Verrouillage automatique',
        'Après ${config.lockAfter.inSeconds} s en arrière-plan ou ${config.idleLock.inMinutes} min sans activité',
        true,
      ),
      _Check(
        Icons.screenshot_monitor_outlined,
        "Protection de l'écran",
        device.screenProtected ? 'Captures et enregistrements bloqués' : 'Contenu masqué dans le multitâche',
        true,
      ),
      _Check(
        device.rooted ? Icons.gpp_bad_outlined : Icons.phonelink_lock_outlined,
        "Intégrité de l'appareil",
        !device.known
            ? 'Vérification disponible sur Android'
            : device.rooted
                ? 'Appareil rooté : évitez les opérations sensibles'
                : 'Aucune modification du système détectée',
        !device.rooted,
      ),
      const _Check(Icons.lock_outline_rounded, 'Données chiffrées', 'Jetons et code stockés dans le coffre-fort du téléphone', true),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Centre de sécurité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          _ScoreCard(checks: checks),
          const SizedBox(height: 18),
          const SectionHeader('Protections'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final c in checks)
                  ListTile(
                    leading: IconBadge(c.icon, size: 40),
                    title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.detail),
                    trailing: Icon(
                      c.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: c.ok ? AppColors.green : AppColors.amber,
                    ),
                  ),
              ],
            ),
          ),
          if (session.previousAccess != null) ...[
            const SizedBox(height: 12),
            InfoBanner(
              'Accès précédent : ${DateFormat("EEEE d MMMM 'à' HH:mm", 'fr_FR').format(session.previousAccess!)}. '
              "Si ce n'était pas vous, changez votre mot de passe et votre code PIN.",
              icon: Icons.history_rounded,
            ),
          ],
          const SizedBox(height: 18),
          const SectionHeader('Double authentification (MFA)'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const IconBadge(Icons.key_rounded, color: AppColors.indigo, size: 40),
                  title: const Text('Méthode', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(session.auth.mfaLabel),
                  trailing: const Icon(Icons.check_circle_rounded, color: AppColors.green),
                ),
                ListTile(
                  leading: const IconBadge(Icons.hub_rounded, color: AppColors.violet, size: 40),
                  title: const Text("Fournisseur d'identité", style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(provider),
                ),
                if (config.authMode == AuthMode.keycloak)
                  ListTile(
                    leading: const IconBadge(Icons.devices_rounded, color: AppColors.sky, size: 40),
                    title: const Text('Gérer mes appareils et mon OTP', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(config.keycloakAccountUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.copy_rounded),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: config.keycloakAccountUrl));
                      showSnack(context, 'Lien de votre espace sécurité copié');
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader('Accès à l\'application'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const IconBadge(Icons.pin_rounded, color: AppColors.amber, size: 40),
                  title: const Text('Modifier mon code PIN', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final ok = await confirmWithPin(context, title: 'Code actuel', summary: 'Saisissez votre code PIN actuel');
                    if (ok && context.mounted) push(context, const PinSetupScreen(changing: true));
                  },
                ),
                SwitchListTile(
                  secondary: const IconBadge(Icons.fingerprint_rounded, color: AppColors.teal, size: 40),
                  title: const Text('Face ID / empreinte', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(session.biometricsAvailable ? 'Déverrouillage et validation rapides' : 'Non disponible sur cet appareil'),
                  value: session.biometricsEnabled,
                  onChanged: session.biometricsAvailable ? session.setBiometrics : null,
                ),
                ListTile(
                  leading: const IconBadge(Icons.timer_outlined, color: AppColors.sky, size: 40),
                  title: const Text('Verrouillage automatique', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Après ${config.lockAfter.inSeconds} s en arrière-plan'),
                ),
                ListTile(
                  leading: const IconBadge(Icons.lock_clock_rounded, color: AppColors.red, size: 40),
                  title: const Text('Verrouiller maintenant', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: session.lockNow,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const InfoBanner(
            'Votre banque ne vous demandera jamais votre mot de passe, votre code PIN ou un code OTP par téléphone, SMS ou e-mail.',
            icon: Icons.privacy_tip_outlined,
            color: AppColors.amber,
          ),
        ],
      ),
    );
  }
}

class _Check {
  const _Check(this.icon, this.title, this.detail, this.ok);
  final IconData icon;
  final String title;
  final String detail;
  final bool ok;
}

/// Score de protection : anneau de progression et résumé.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.checks});
  final List<_Check> checks;

  @override
  Widget build(BuildContext context) {
    final ok = checks.where((c) => c.ok).length;
    final ratio = ok / checks.length;
    final full = ok == checks.length;
    return GradientCard(
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: v,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(full ? AppColors.gold : AppColors.amber),
                  ),
                  Center(
                    child: Text('$ok/${checks.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(full ? 'Protection maximale' : 'Protection à renforcer',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 4),
                Text(
                  full ? 'Toutes les protections de votre compte sont actives.' : 'Activez les protections signalées ci-dessous.',
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
