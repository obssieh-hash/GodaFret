import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import 'common.dart';

(IconData, Color) txVisual(TxKind kind) => switch (kind) {
      TxKind.deposit => (Icons.south_west_rounded, AppColors.green),
      TxKind.withdrawal => (Icons.north_east_rounded, AppColors.red),
      TxKind.transferIn => (Icons.call_received_rounded, AppColors.teal),
      TxKind.transferOut => (Icons.send_rounded, AppColors.violet),
      TxKind.disbursement => (Icons.account_balance_rounded, AppColors.sky),
      TxKind.repayment => (Icons.payments_rounded, AppColors.amber),
      TxKind.fee => (Icons.receipt_long_rounded, AppColors.red),
      TxKind.interest => (Icons.trending_up_rounded, AppColors.green),
      TxKind.other => (Icons.swap_horiz_rounded, AppColors.indigo),
    };

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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _details(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            IconBadge(icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
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
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
              IconBadge(icon, color: color, size: 64),
              const SizedBox(height: 14),
              MoneyText(
                tx.amount,
                currency: tx.currency,
                signed: true,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
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
