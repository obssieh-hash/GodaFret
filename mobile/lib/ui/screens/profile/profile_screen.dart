import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../state/bank_controller.dart';
import '../../../state/session_controller.dart';
import '../../../state/theme_controller.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import 'notifications_screen.dart';
import 'security_screen.dart';

/// 👤 Profil utilisateur.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final session = context.watch<SessionController>();
    final theme = context.watch<ThemeController>();
    final client = bank.client;
    if (client == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          GradientCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                  child: Avatar(client.displayName, size: 64),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(client.displayName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Client n° ${client.accountNo}', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(client.status, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader('Informations personnelles'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _InfoTile(Icons.badge_outlined, 'Identifiant', session.auth.username ?? client.externalId ?? '—'),
                _InfoTile(Icons.phone_iphone_rounded, 'Téléphone', client.mobileNo ?? '—'),
                _InfoTile(Icons.alternate_email_rounded, 'E-mail', client.email ?? '—'),
                _InfoTile(Icons.store_mall_directory_outlined, 'Agence', client.officeName ?? '—'),
                _InfoTile(Icons.calendar_month_outlined, 'Client depuis', Fmt.date(client.activationDate)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader('Préférences'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _NavTile(
                  icon: Icons.shield_outlined,
                  color: AppColors.indigo,
                  title: 'Sécurité & MFA',
                  subtitle: 'Code PIN, biométrie, double authentification',
                  onTap: () => push(context, const SecurityScreen()),
                ),
                _NavTile(
                  icon: Icons.notifications_none_rounded,
                  color: AppColors.amber,
                  title: 'Notifications',
                  subtitle: bank.unreadCount == 0 ? 'Tout est lu' : '${bank.unreadCount} non lue(s)',
                  onTap: () => push(context, const NotificationsScreen()),
                ),
                ListTile(
                  leading: const IconBadge(Icons.dark_mode_outlined, color: AppColors.violet, size: 40),
                  title: const Text('Apparence', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18)),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded, size: 18)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18)),
                    ],
                    selected: {theme.mode},
                    onSelectionChanged: (s) => theme.set(s.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Se déconnecter ?'),
                  content: const Text('Vous devrez saisir à nouveau votre mot de passe et votre code OTP.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Déconnexion')),
                  ],
                ),
              );
              if (ok == true) await session.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'GodaFret Banque · propulsé par Apache Fineract',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        subtitle: Text(value, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: IconBadge(icon, color: color, size: 40),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      );
}
