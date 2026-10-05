import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          GradientCard(
            gradient: AppColors.tealGradient,
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Colors.white, size: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Protection forte active',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 4),
                      Text(
                        'Mot de passe · ${session.auth.mfaLabel} · code PIN',
                        style: const TextStyle(color: Colors.white70, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
