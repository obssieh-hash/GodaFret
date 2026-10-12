import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../wallet/receive_screen.dart';
import '../wallet/send_screen.dart';
import 'home_shell.dart';

/// Onglet « Paiements » : toutes les façons de faire circuler l'argent.
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final recents = <String>{
      for (final t in bank.history)
        if (t.kind == TxKind.transferOut && counterpart(t.label) != null) counterpart(t.label)!,
    }.take(6).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 18),
              child: Text('Paiements', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
            ),
            if (recents.isNotEmpty) ...[
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recents.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _Person(
                        label: 'Nouveau',
                        child: const IconBadge(Icons.add_rounded, size: 56, filled: true),
                        onTap: () => push(context, const SendScreen()),
                      );
                    }
                    final name = recents[i - 1];
                    return _Person(
                      label: name.split(' ').first,
                      child: Avatar(name, size: 56),
                      onTap: () => push(context, const SendScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
            ],
            const _Group(title: 'Envoyer et payer', items: [
              (Icons.north_east_rounded, "Envoyer de l'argent", 'À un numéro Golden Bridge, instantanément', _Target.send),
              (Icons.qr_code_2_rounded, 'Payer un marchand', 'Boutiques et services partenaires', _Target.merchant),
              (Icons.payments_outlined, 'Retrait chez un agent', 'Recevez des espèces près de chez vous', _Target.agent),
            ]),
            const SizedBox(height: 16),
            const _Group(title: 'Recevoir', items: [
              (Icons.south_west_rounded, "Recevoir de l'argent", 'Votre numéro et votre QR code', _Target.receive),
              (Icons.add_rounded, 'Déposer des espèces', 'Chez un agent ou en agence', _Target.deposit),
            ]),
            const SizedBox(height: 16),
            if (bank.savings.isNotEmpty)
              Text(
                'Solde disponible : ${bank.balanceHidden ? '•••' : Fmt.money(bank.savings.first.available, currency: bank.currency)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

enum _Target { send, merchant, agent, receive, deposit }

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items});
  final String title;
  final List<(IconData, String, String, _Target)> items;

  void _open(BuildContext context, _Target t) => push(
        context,
        switch (t) {
          _Target.send => const SendScreen(),
          _Target.merchant => const SendScreen(mode: SendMode.merchant),
          _Target.agent => const SendScreen(mode: SendMode.agent),
          _Target.receive => const ReceiveScreen(),
          _Target.deposit => const ReceiveScreen(deposit: true),
        },
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (icon, label, subtitle, target) in items)
                  ListTile(
                    leading: IconBadge(icon, filled: true, size: 40),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(subtitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _open(context, target),
                  ),
              ],
            ),
          ),
        ],
      );
}

class _Person extends StatelessWidget {
  const _Person({required this.label, required this.child, required this.onTap});
  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              child,
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      );
}
