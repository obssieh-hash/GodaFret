import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../../state/session_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../accounts/account_detail_screen.dart';
import '../loans/loan_detail_screen.dart';
import '../loans/loan_request_screen.dart';
import '../loans/repayment_screen.dart';
import '../operations/operation_screen.dart';
import '../operations/transfer_screen.dart';
import '../profile/notifications_screen.dart';
import '../profile/security_screen.dart';
import 'home_shell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final session = context.watch<SessionController>();

    if (!bank.loaded) {
      return Scaffold(
        body: Center(
          child: bank.error != null
              ? Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(bank.error!, onRetry: bank.refresh))
              : const CircularProgressIndicator(),
        ),
      );
    }

    final client = bank.client!;
    final hidden = bank.balanceHidden;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                sliver: SliverList.list(
                  children: [
                    _Header(name: session.auth.fullName ?? client.displayName, unread: bank.unreadCount),
                    const SizedBox(height: 20),
                    _BalanceCard(bank: bank),
                    if (bank.error != null) ...[const SizedBox(height: 14), ErrorBanner(bank.error!, onRetry: bank.refresh)],
                    const SizedBox(height: 24),
                    const _QuickActions(),
                    const SizedBox(height: 18),
                    SectionHeader(
                      'Mes comptes',
                      action: 'Tout voir',
                      onAction: () => HomeShell.of(context)?.go(HomeShellState.tabAccounts),
                    ),
                    _AccountsCarousel(accounts: bank.savings, hidden: hidden),
                    if (bank.nextInstallment != null) ...[
                      const SizedBox(height: 22),
                      _NextInstallmentCard(loan: bank.nextInstallment!.$1, installment: bank.nextInstallment!.$2, hidden: hidden),
                    ],
                    const SizedBox(height: 22),
                    _CashflowCard(stats: bank.monthlyStats(), currency: bank.currency, hidden: hidden),
                    const SizedBox(height: 22),
                    SectionHeader(
                      'Dernières opérations',
                      action: 'Historique',
                      onAction: () => HomeShell.of(context)?.go(HomeShellState.tabHistory),
                    ),
                    SurfaceCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: bank.history.isEmpty
                          ? const EmptyState(icon: Icons.receipt_long_rounded, title: 'Aucune opération pour le moment')
                          : Column(
                              children: [
                                for (final t in bank.history.take(5)) TransactionTile(t, hidden: hidden),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.unread});
  final String name;
  final int unread;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5 || h >= 18) return 'Bonsoir';
    return 'Bonjour';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        GestureDetector(
          onTap: () => HomeShell.of(context)?.go(HomeShellState.tabProfile),
          child: Avatar(name),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_greeting, ${name.split(' ').first} 👋',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now())),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
        _RoundIcon(
          icon: Icons.notifications_none_rounded,
          badge: unread,
          onTap: () => push(context, const NotificationsScreen()),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              backgroundColor: AppColors.red,
              child: Icon(icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.bank});
  final BankController bank;

  @override
  Widget build(BuildContext context) {
    final hidden = bank.balanceHidden;
    const label = TextStyle(color: Colors.white70, fontSize: 13);
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Solde total', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: bank.toggleBalance,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white70, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: MoneyText(
              bank.totalBalance,
              key: ValueKey('${bank.totalBalance}-$hidden'),
              currency: bank.currency,
              hidden: hidden,
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Comptes', style: label),
                    const SizedBox(height: 2),
                    Text('${bank.savings.length} actif${bank.savings.length > 1 ? 's' : ''}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Encours de prêts', style: label),
                    const SizedBox(height: 2),
                    MoneyText(
                      bank.totalDebt,
                      currency: bank.currency,
                      hidden: hidden,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (bank.loading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, Color, VoidCallback)>[
      (Icons.add_rounded, 'Dépôt', AppColors.green, () => push(context, const OperationScreen(type: OperationType.deposit))),
      (Icons.remove_rounded, 'Retrait', AppColors.red, () => push(context, const OperationScreen(type: OperationType.withdrawal))),
      (Icons.swap_horiz_rounded, 'Transfert', AppColors.violet, () => push(context, const TransferScreen())),
      (Icons.request_quote_rounded, 'Prêt', AppColors.sky, () => push(context, const LoanRequestScreen())),
      (Icons.payments_rounded, 'Rembourser', AppColors.amber, () => push(context, const RepaymentScreen())),
      (Icons.event_note_rounded, 'Échéancier', AppColors.teal, () => _openSchedule(context)),
      (Icons.history_rounded, 'Historique', AppColors.indigo, () => HomeShell.of(context)?.go(HomeShellState.tabHistory)),
      (Icons.shield_rounded, 'Sécurité', const Color(0xFFDB2777), () => push(context, const SecurityScreen())),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 8,
      childAspectRatio: 0.82,
      children: [
        for (final (icon, label, color, onTap) in actions)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Icon(icon, color: color, size: 27),
                ),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
      ],
    );
  }

  void _openSchedule(BuildContext context) {
    final loans = context.read<BankController>().activeLoans;
    if (loans.isEmpty) {
      showSnack(context, "Vous n'avez aucun prêt en cours.");
    } else if (loans.length == 1) {
      push(context, LoanDetailScreen(loanId: loans.first.id));
    } else {
      HomeShell.of(context)?.go(HomeShellState.tabLoans);
    }
  }
}

class _AccountsCarousel extends StatelessWidget {
  const _AccountsCarousel({required this.accounts, required this.hidden});
  final List<SavingsAccount> accounts;
  final bool hidden;

  static const _gradients = [AppColors.nightGradient, AppColors.tealGradient, AppColors.sunsetGradient];

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const SurfaceCard(child: EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'Aucun compte actif'));
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: accounts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final a = accounts[i];
          return SizedBox(
            width: 240,
            child: GradientCard(
              gradient: _gradients[i % _gradients.length],
              padding: const EdgeInsets.all(18),
              radius: 24,
              onTap: () => push(context, AccountDetailScreen(accountId: a.id)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(a.productName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  MoneyText(
                    a.balance,
                    currency: a.currency,
                    hidden: hidden,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(Fmt.maskAccount(a.accountNo), style: const TextStyle(color: Colors.white60, letterSpacing: 1.2)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NextInstallmentCard extends StatelessWidget {
  const _NextInstallmentCard({required this.loan, required this.installment, required this.hidden});
  final LoanAccount loan;
  final Installment installment;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final days = installment.dueDate.difference(DateTime.now()).inDays;
    final color = installment.overdue ? AppColors.red : (days <= 5 ? AppColors.amber : AppColors.teal);
    return SurfaceCard(
      onTap: () => push(context, LoanDetailScreen(loanId: loan.id)),
      child: Row(
        children: [
          IconBadge(Icons.event_available_rounded, color: color, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Prochaine échéance', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  installment.overdue
                      ? '${loan.productName} · en retard depuis le ${Fmt.shortDate(installment.dueDate)}'
                      : '${loan.productName} · ${Fmt.shortDate(installment.dueDate)} (J-${days < 0 ? 0 : days})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
          MoneyText(
            installment.outstanding,
            currency: loan.currency,
            hidden: hidden,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _CashflowCard extends StatelessWidget {
  const _CashflowCard({required this.stats, required this.currency, required this.hidden});
  final List<MonthStat> stats;
  final String currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = stats.last;
    final maxY = stats.fold<double>(0, (m, s) => [m, s.income, s.expenses].reduce((a, b) => a > b ? a : b));
    final savingsRate = current.income <= 0 ? 0.0 : ((current.income - current.expenses) / current.income).clamp(-1.0, 1.0);

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Tableau de bord', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              _Legend(color: AppColors.teal, label: 'Entrées'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.violet, label: 'Sorties'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(label: 'Entrées du mois', value: hidden ? '•••' : Fmt.compact(current.income, currency: currency), color: AppColors.green),
              _Metric(label: 'Sorties du mois', value: hidden ? '•••' : Fmt.compact(current.expenses, currency: currency), color: AppColors.red),
              _Metric(
                label: "Taux d'épargne",
                value: '${(savingsRate * 100).round()} %',
                color: savingsRate >= 0 ? AppColors.indigo : AppColors.red,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: maxY <= 0 ? 1 : maxY * 1.15,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY <= 0 ? 1 : maxY / 3,
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.35), strokeWidth: 1, dashArray: [4, 4]),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          toBeginningOfSentenceCase(DateFormat('MMM', 'fr_FR').format(stats[v.toInt()].month)).replaceAll('.', ''),
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: !hidden,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.night,
                    getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                      '${rodIndex == 0 ? 'Entrées' : 'Sorties'}\n${Fmt.money(rod.toY, currency: currency)}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < stats.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: stats[i].income,
                          width: 10,
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF0F766E), AppColors.teal]),
                        ),
                        BarChartRodData(
                          toY: stats[i].expenses,
                          width: 10,
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [AppColors.indigo, AppColors.violet]),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ],
        ),
      );
}
