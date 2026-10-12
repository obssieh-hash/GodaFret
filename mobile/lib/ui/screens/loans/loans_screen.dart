import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import 'loan_detail_screen.dart';
import 'loan_request_screen.dart';

class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final loans = bank.loanDetails;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 20, 16, 28),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Text('Prêts', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
            ),
            SurfaceCard(
              onTap: () => push(context, const LoanRequestScreen()),
              child: const Row(
                children: [
                  IconBadge(Icons.add_rounded, filled: true, size: 40),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Demander un prêt', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Simulation immédiate, réponse de votre agence'),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (loans.isEmpty)
              const EmptyState(
                icon: Icons.credit_card_off_rounded,
                title: 'Aucun prêt',
                message: 'Vos prêts et demandes apparaîtront ici.',
              )
            else
              for (final l in loans) ...[
                LoanCard(loan: l, hidden: bank.balanceHidden),
                const SizedBox(height: 14),
              ],
          ],
        ),
      ),
    );
  }
}

(String, Color) loanStateVisual(LoanState s) => switch (s) {
      LoanState.pending => ("En attente d'approbation", AppColors.amber),
      LoanState.approved => ('Approuvé · en attente de décaissement', AppColors.sky),
      LoanState.active => ('En cours', AppColors.green),
      LoanState.closed => ('Soldé', AppColors.indigo),
      LoanState.rejected => ('Refusé / retiré', AppColors.red),
      LoanState.other => ('—', Colors.grey),
    };

class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.loan, required this.hidden});
  final LoanAccount loan;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final (label, color) = loanStateVisual(loan.state);
    final scheme = Theme.of(context).colorScheme;
    final paidRatio = loan.state == LoanState.active ? loan.progress : (loan.state == LoanState.closed ? 1.0 : 0.0);
    final next = loan.nextInstallment;
    return SurfaceCard(
      onTap: () => push(context, LoanDetailScreen(loanId: loan.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.credit_card_rounded, color: AppColors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loan.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('N° ${loan.accountNo}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label.split(' · ').first, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _Figure('Montant', hidden ? '•••' : Fmt.money(loan.principal, currency: loan.currency))),
              Expanded(child: _Figure('Restant dû', hidden ? '•••' : Fmt.money(loan.outstanding, currency: loan.currency))),
            ],
          ),
          if (loan.state == LoanState.active) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: paidRatio,
                minHeight: 9,
                backgroundColor: scheme.primary.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(AppColors.teal),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('${(paidRatio * 100).round()} % remboursé',
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ),
                if (next != null)
                  Flexible(
                    child: Text('Prochaine : ${Fmt.shortDate(next.dueDate)}',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: next.overdue ? AppColors.red : null)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      );
}
