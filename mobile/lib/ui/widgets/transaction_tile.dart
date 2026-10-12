import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import 'common.dart';

(IconData, Color) txVisual(TxKind kind) => switch (kind) {
      TxKind.deposit => (Icons.add_rounded, AppColors.ink),
      TxKind.withdrawal => (Icons.payments_outlined, AppColors.ink),
      TxKind.transferIn => (Icons.south_west_rounded, AppColors.ink),
      TxKind.transferOut => (Icons.north_east_rounded, AppColors.ink),
      TxKind.disbursement => (Icons.account_balance_outlined, AppColors.ink),
      TxKind.repayment => (Icons.event_available_outlined, AppColors.ink),
      TxKind.fee => (Icons.receipt_long_outlined, AppColors.ink),
      TxKind.interest => (Icons.percent_rounded, AppColors.ink),
      TxKind.other => (Icons.swap_horiz_rounded, AppColors.ink),
    };

/// Nom de la contrepartie extrait du libellé (« Envoi à Ahmed » → « Ahmed »), sinon `null`.
String? counterpart(String label) {
  for (final p in ['Envoi à ', 'Paiement ', 'Retrait chez ', 'Reçu de ', 'Loyer · ']) {
    final i = label.indexOf(p);
    if (i >= 0) return label.substring(i + p.length).split(' · ').first;
  }
  return null;
}

class TransactionTile extends StatelessWidget {
  const TransactionTile(this.tx, {super.key, this.hidden = false, this.showAccount = true});

  final BankTransaction tx;
  final bool hidden;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = txVisual(tx.kind);
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      Fmt.shortDate(tx.date),
      if (showAccount && tx.accountLabel != null) tx.accountLabel!,
    ].join(' · ');
    final who = counterpart(tx.label);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _details(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            who != null ? Avatar(who, size: 42) : Avatar(tx.label, size: 42, icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MoneyText(
              tx.amount,
              currency: tx.currency,
              hidden: hidden,
              signed: true,
              colored: true,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  void _details(BuildContext context) {
    final (icon, color) = txVisual(tx.kind);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(counterpart(tx.label) ?? tx.label, size: 64, icon: counterpart(tx.label) == null ? icon : null),
              const SizedBox(height: 14),
              MoneyText(
                tx.amount,
                currency: tx.currency,
                signed: true,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8),
              ),
              const SizedBox(height: 4),
              Text(tx.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              KeyValueRow('Date', Fmt.date(tx.date)),
              if (tx.accountLabel != null) KeyValueRow(tx.isLoan ? 'Prêt' : 'Compte', tx.accountLabel!),
              if (tx.runningBalance != null)
                KeyValueRow(
                  tx.isLoan ? 'Capital restant après opération' : 'Solde après opération',
                  Fmt.money(tx.runningBalance!, currency: tx.currency),
                ),
              KeyValueRow('Référence', '#${tx.id}'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste de transactions groupées par jour.
class GroupedTransactions extends StatelessWidget {
  const GroupedTransactions(this.transactions, {super.key, this.hidden = false, this.showAccount = true});

  final List<BankTransaction> transactions;
  final bool hidden;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    DateTime? day;
    for (final t in transactions) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      if (day != d) {
        day = d;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            _capitalize(Fmt.dayHeader(d)),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ));
      }
      children.add(TransactionTile(t, hidden: hidden, showAccount: showAccount));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
