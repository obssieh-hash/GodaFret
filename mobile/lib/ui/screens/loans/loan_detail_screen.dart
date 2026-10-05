import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../home/home_shell.dart';
import 'loans_screen.dart';
import 'repayment_screen.dart';

/// Détail d'un prêt : progression, 📅 échéancier et opérations.
class LoanDetailScreen extends StatelessWidget {
  const LoanDetailScreen({super.key, required this.loanId});
  final int loanId;

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final loan = bank.loanDetails.where((l) => l.id == loanId).firstOrNull;
    if (loan == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off_rounded, title: 'Prêt introuvable'));
    }
    final hidden = bank.balanceHidden;
    final (stateLabel, stateColor) = loanStateVisual(loan.state);
    final next = loan.nextInstallment;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(loan.productName)),
        bottomNavigationBar: loan.state == LoanState.active
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: PrimaryButton(
                    label: 'Rembourser',
                    icon: Icons.payments_rounded,
                    onPressed: () => push(context, RepaymentScreen(loanId: loan.id)),
                  ),
                ),
              )
            : null,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  children: [
                    GradientCard(
                      gradient: AppColors.nightGradient,
                      child: Row(
                        children: [
                          _ProgressRing(value: loan.state == LoanState.closed ? 1 : loan.progress),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Restant dû', style: TextStyle(color: Colors.white60)),
                                MoneyText(
                                  loan.outstanding,
                                  currency: loan.currency,
                                  hidden: hidden,
                                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: stateColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(stateLabel, style: TextStyle(color: stateColor, fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SurfaceCard(
                      child: Column(
                        children: [
                          KeyValueRow('Montant emprunté', hidden ? '•••' : Fmt.money(loan.principal, currency: loan.currency)),
                          KeyValueRow('Déjà remboursé', hidden ? '•••' : Fmt.money(loan.amountPaid, currency: loan.currency)),
                          if (loan.interestRate != null)
                            KeyValueRow('Taux par période', '${loan.interestRate!.toStringAsFixed(2).replaceAll('.', ',')} %'),
                          if (loan.numberOfRepayments != null) KeyValueRow('Nombre d\'échéances', '${loan.numberOfRepayments}'),
                          if (loan.overdue > 0)
                            KeyValueRow('Impayés', Fmt.money(loan.overdue, currency: loan.currency), valueColor: AppColors.red, bold: true),
                          if (next != null)
                            KeyValueRow(
                              'Prochaine échéance',
                              '${Fmt.date(next.dueDate)} · ${hidden ? '•••' : Fmt.money(next.outstanding, currency: loan.currency)}',
                              bold: true,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(pinned: true, delegate: _TabsHeader(Theme.of(context).scaffoldBackgroundColor)),
          ],
          body: TabBarView(
            children: [
              _ScheduleList(loan: loan, hidden: hidden),
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (loan.transactions.isEmpty)
                    const EmptyState(icon: Icons.receipt_long_rounded, title: 'Aucune opération')
                  else
                    SurfaceCard(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: GroupedTransactions(
                        [...loan.transactions]..sort((a, b) => b.date.compareTo(a.date)),
                        hidden: hidden,
                        showAccount: false,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.background);
  final Color background;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: background,
        child: const TabBar(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [Tab(text: 'Échéancier'), Tab(text: 'Opérations')],
        ),
      );

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.background != background;
}

class _ScheduleList extends StatelessWidget {
  const _ScheduleList({required this.loan, required this.hidden});
  final LoanAccount loan;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    if (loan.schedule.isEmpty) {
      return const EmptyState(
        icon: Icons.event_note_rounded,
        title: 'Échéancier indisponible',
        message: 'Il sera disponible après l\'approbation du prêt.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final nextNumber = loan.nextInstallment?.number;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: loan.schedule.length,
      itemBuilder: (context, i) {
        final it = loan.schedule[i];
        final isNext = it.number == nextNumber;
        final (icon, color) = it.complete
            ? (Icons.check_circle_rounded, AppColors.green)
            : it.overdue
                ? (Icons.error_rounded, AppColors.red)
                : isNext
                    ? (Icons.radio_button_checked_rounded, AppColors.indigo)
                    : (Icons.radio_button_unchecked_rounded, scheme.outline);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isNext ? scheme.primary.withValues(alpha: 0.07) : scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: isNext ? Border.all(color: scheme.primary.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              SizedBox(
                width: 34,
                child: Text('${it.number}', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.date(it.dueDate), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      hidden
                          ? 'Capital • Intérêts'
                          : 'Capital ${Fmt.money(it.principal, currency: loan.currency)} · Intérêts ${Fmt.money(it.interest, currency: loan.currency)}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                hidden ? '•••' : Fmt.money(it.totalDue, currency: loan.currency),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  decoration: it.complete ? TextDecoration.lineThrough : null,
                  color: it.complete ? scheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 96,
        height: 96,
        child: CustomPaint(
          painter: _RingPainter(v),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(v * 100).round()} %', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                const Text('remboursé', style: TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.1;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, 2 * pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.12));
    canvas.drawArc(
      r,
      -pi / 2,
      2 * pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [AppColors.teal, Color(0xFF5EEAD4), AppColors.teal]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}
