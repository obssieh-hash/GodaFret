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
      appBar: AppBar(title: const Text('Mes prêts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, const LoanRequestScreen()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Demander un prêt'),
      ),
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            GradientCard(
              gradient: AppColors.sunsetGradient,
              onTap: () => push(context, const LoanRequestScreen()),
              child: const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Un projet en tête ?', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                        SizedBox(height: 6),
                        Text(
                          'Simulez votre mensualité et envoyez votre demande en 2 minutes.',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 44),
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
