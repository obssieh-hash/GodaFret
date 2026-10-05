import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';

enum _Filter { all, credits, debits, transfers, loans }

/// 📜 Historique de toutes les opérations, filtrable.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

  bool _match(BankTransaction t) {
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.credits => t.amount >= 0 && !t.isLoan,
      _Filter.debits => t.amount < 0 && !t.isLoan,
      _Filter.transfers => t.kind == TxKind.transferIn || t.kind == TxKind.transferOut,
      _Filter.loans => t.isLoan,
    };
    if (!ok) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return t.label.toLowerCase().contains(q) || (t.accountLabel ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final items = bank.history.where(_match).toList();
    final inSum = items.where((t) => t.amount > 0).fold<double>(0, (s, t) => s + t.amount);
    final outSum = items.where((t) => t.amount < 0).fold<double>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: const InputDecoration(
                hintText: 'Rechercher une opération',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (f, label) in const [
                    (_Filter.all, 'Tout'),
                    (_Filter.credits, 'Entrées'),
                    (_Filter.debits, 'Sorties'),
                    (_Filter.transfers, 'Transferts'),
                    (_Filter.loans, 'Prêts'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Total(label: 'Entrées', value: inSum, color: AppColors.green, hidden: bank.balanceHidden, currency: bank.currency)),
                const SizedBox(width: 12),
                Expanded(child: _Total(label: 'Sorties', value: outSum, color: AppColors.red, hidden: bank.balanceHidden, currency: bank.currency)),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const EmptyState(icon: Icons.search_off_rounded, title: 'Aucune opération', message: 'Modifiez les filtres ou la recherche.')
            else
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: GroupedTransactions(items, hidden: bank.balanceHidden),
              ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color, required this.hidden, required this.currency});
  final String label;
  final double value;
  final Color color;
  final bool hidden;
  final String currency;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              hidden ? '•••' : Fmt.money(value, currency: currency),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color),
            ),
          ],
        ),
      );
}
