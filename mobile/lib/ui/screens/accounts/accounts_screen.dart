import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import '../loans/loan_detail_screen.dart';
import 'account_detail_screen.dart';

/// 💰 Soldes de tous les comptes.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final hidden = bank.balanceHidden;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes comptes'),
        actions: [
          IconButton(
            tooltip: hidden ? 'Afficher les montants' : 'Masquer les montants',
            onPressed: bank.toggleBalance,
            icon: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            GradientCard(
              gradient: AppColors.nightGradient,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Patrimoine net', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        MoneyText(
                          bank.totalBalance - bank.totalDebt,
                          currency: bank.currency,
                          hidden: hidden,
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bank.updatedAt == null ? '' : 'Mis à jour ${Fmt.relative(bank.updatedAt!).toLowerCase()}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.account_balance_rounded, color: Colors.white38, size: 46),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Comptes de dépôt'),
            if (bank.savings.isEmpty)
              const SurfaceCard(child: EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'Aucun compte actif'))
            else
              for (final a in bank.savings) ...[
                SurfaceCard(
                  onTap: () => push(context, AccountDetailScreen(accountId: a.id)),
                  child: Row(
                    children: [
                      const IconBadge(Icons.account_balance_wallet_rounded, color: AppColors.indigo, size: 50),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                            const SizedBox(height: 3),
                            Text('N° ${a.accountNo}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(a.balance,
                              currency: a.currency, hidden: hidden, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          if (a.availableBalance != null && a.availableBalance != a.balance)
                            Text(
                              hidden ? 'Disponible' : 'Dispo. ${Fmt.money(a.available, currency: a.currency)}',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 10),
            const SectionHeader('Crédits'),
            if (bank.loanDetails.isEmpty)
              const SurfaceCard(child: EmptyState(icon: Icons.credit_card_outlined, title: 'Aucun prêt'))
            else
              for (final l in bank.loanDetails) ...[
                SurfaceCard(
                  onTap: () => push(context, LoanDetailScreen(loanId: l.id)),
                  child: Row(
                    children: [
                      const IconBadge(Icons.credit_card_rounded, color: AppColors.amber, size: 50),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                            const SizedBox(height: 3),
                            Text(l.statusLabel,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                      MoneyText(-l.outstanding,
                          currency: l.currency, hidden: hidden, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}
