import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';

/// 🔔 Notifications Fineract (`GET /notifications`).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  (IconData, Color) _visual(AppNotification n) {
    final t = '${n.objectType ?? ''} ${n.title}'.toLowerCase();
    if (t.contains('prêt') || t.contains('loan') || t.contains('échéance')) return (Icons.credit_card_rounded, AppColors.amber);
    if (t.contains('sécurité') || t.contains('connexion')) return (Icons.shield_rounded, AppColors.violet);
    if (t.contains('transfert')) return (Icons.swap_horiz_rounded, AppColors.indigo);
    if (t.contains('retrait')) return (Icons.north_east_rounded, AppColors.red);
    return (Icons.notifications_rounded, AppColors.teal);
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final items = bank.notifications;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (bank.unreadCount > 0)
            TextButton(onPressed: bank.markNotificationsRead, child: const Text('Tout lire')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: items.isEmpty
            ? ListView(
                children: const [
                  EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'Aucune notification',
                    message: 'Vous serez informé ici de chaque mouvement important.',
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final n = items[i];
                  final (icon, color) = _visual(n);
                  return SurfaceCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(icon, color: color),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(n.title,
                                        style: TextStyle(fontWeight: n.read ? FontWeight.w600 : FontWeight.w800)),
                                  ),
                                  if (!n.read)
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(n.body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35)),
                              const SizedBox(height: 6),
                              Text(Fmt.relative(n.createdAt),
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
