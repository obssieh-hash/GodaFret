import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../services/bank_repository.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../home/home_shell.dart';
import '../wallet/receive_screen.dart';
import '../wallet/send_screen.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});
  final int accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late Future<SavingsDetail> _future = _load();
  int? _lastRefresh;

  Future<SavingsDetail> _load() => context.read<BankController>().repo.savingsDetail(widget.accountId);

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    // Recharge après une opération (le contrôleur a été rafraîchi).
    final stamp = bank.updatedAt?.millisecondsSinceEpoch;
    if (_lastRefresh != null && stamp != _lastRefresh) _future = _load();
    _lastRefresh = stamp;

    return Scaffold(
      appBar: AppBar(title: const Text('Détail du compte')),
      body: FutureBuilder<SavingsDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ErrorBanner('${snap.error}', onRetry: () => setState(() => _future = _load())),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final a = d.account;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                GradientCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: a.accountNo));
                          showSnack(context, 'Numéro de compte copié');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('N° ${a.accountNo}', style: const TextStyle(color: Colors.white70, letterSpacing: 1)),
                            const SizedBox(width: 6),
                            const Icon(Icons.copy_rounded, size: 14, color: Colors.white54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text('Solde', style: TextStyle(color: Colors.white70)),
                      MoneyText(
                        a.balance,
                        currency: a.currency,
                        hidden: bank.balanceHidden,
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1),
                      ),
                      if (a.availableBalance != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Disponible : ${bank.balanceHidden ? '•••' : Fmt.money(a.available, currency: a.currency)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Action(
                      icon: Icons.send_rounded,
                      label: 'Envoyer',
                      color: AppColors.violet,
                      onTap: () => push(context, const SendScreen()),
                    ),
                    _Action(
                      icon: Icons.qr_code_2_rounded,
                      label: 'Recevoir',
                      color: AppColors.indigo,
                      onTap: () => push(context, const ReceiveScreen()),
                    ),
                    _Action(
                      icon: Icons.payments_outlined,
                      label: 'Retrait',
                      color: AppColors.amber,
                      onTap: () => push(context, const SendScreen(mode: SendMode.agent)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionHeader('Opérations'),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: d.transactions.isEmpty
                      ? const EmptyState(icon: Icons.receipt_long_rounded, title: 'Aucune opération')
                      : GroupedTransactions(d.transactions, hidden: bank.balanceHidden, showAccount: false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: onTap,
            child: Column(
              children: [
                IconBadge(icon, color: color, size: 42),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}
