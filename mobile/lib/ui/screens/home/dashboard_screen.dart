import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/brand.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../../state/session_controller.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../accounts/accounts_screen.dart';
import '../loans/loan_detail_screen.dart';
import '../loans/loans_screen.dart';
import '../loans/repayment_screen.dart';
import '../profile/notifications_screen.dart';
import '../wallet/receive_screen.dart';
import '../wallet/send_screen.dart';
import 'home_shell.dart';

/// Accueil façon portefeuille mobile : solde, 8 actions, dernières opérations.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();

    if (!bank.loaded) {
      return Scaffold(
        body: Center(
          child: bank.error != null
              ? Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(bank.error!, onRetry: bank.refresh))
              : const CircularProgressIndicator(),
        ),
      );
    }

    final hidden = bank.balanceHidden;
    final month = bank.monthlyStats(months: 1).first;
    final next = bank.nextInstallment;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _Header(),
            Transform.translate(
              offset: const Offset(0, -34),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _Actions(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (bank.error != null) ...[ErrorBanner(bank.error!, onRetry: bank.refresh), const SizedBox(height: 14)],
                  Row(
                    children: [
                      Expanded(
                        child: _MonthTile(
                          label: 'Reçu ce mois',
                          value: hidden ? '•••' : Fmt.money(month.income, currency: bank.currency),
                          icon: Icons.south_west_rounded,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MonthTile(
                          label: 'Dépensé ce mois',
                          value: hidden ? '•••' : Fmt.money(month.expenses, currency: bank.currency),
                          icon: Icons.north_east_rounded,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 14),
                    _NextInstallmentCard(loan: next.$1, installment: next.$2, hidden: hidden),
                  ],
                  const SizedBox(height: 18),
                  SectionHeader(
                    'Dernières opérations',
                    action: 'Tout voir',
                    onAction: () => HomeShell.of(context)?.go(HomeShellState.tabHistory),
                  ),
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: bank.history.isEmpty
                        ? const EmptyState(icon: Icons.receipt_long_rounded, title: 'Aucune opération pour le moment')
                        : Column(children: [for (final t in bank.history.take(6)) TransactionTile(t, hidden: hidden)]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau bleu nuit : logo, notifications, salutation et solde.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final session = context.watch<SessionController>();
    final client = bank.client!;
    final main = bank.savings.firstOrNull;
    final hidden = bank.balanceHidden;
    final name = (session.auth.fullName ?? client.displayName).split(' ').first;
    final hour = DateTime.now().hour;

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: 20,
            child: Opacity(opacity: 0.08, child: Image.asset(Brand.logoMark, width: 240)),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 54),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Flexible(child: Align(alignment: Alignment.centerLeft, child: BrandWordmark(onDark: true, size: 17))),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Notifications',
                        onPressed: () => push(context, const NotificationsScreen()),
                        icon: Badge(
                          isLabelVisible: bank.unreadCount > 0,
                          label: Text('${bank.unreadCount}'),
                          backgroundColor: AppColors.red,
                          child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${hour < 5 || hour >= 18 ? 'Bonsoir' : 'Bonjour'}, $name',
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Solde disponible', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: bank.toggleBalance,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: Colors.white70,
                            size: 18,
                            semanticLabel: hidden ? 'Afficher le solde' : 'Masquer le solde',
                          ),
                        ),
                      ),
                    ],
                  ),
                  MoneyText(
                    main?.available ?? 0,
                    currency: main?.currency ?? bank.currency,
                    hidden: hidden,
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeaderChip(
                        icon: Icons.phone_iphone_rounded,
                        text: '${Brand.phonePrefix} ${Fmt.phone(client.mobileNo)}',
                      ),
                      if (bank.savings.length > 1 || bank.loanDetails.isNotEmpty)
                        _HeaderChip(
                          icon: Icons.account_balance_wallet_outlined,
                          text: 'Mes comptes',
                          onTap: () => push(context, const AccountsScreen()),
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

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: AppColors.gold),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white70),
              ],
            ),
          ),
        ),
      );
}

/// Grille de 8 grandes actions.
class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, Color, VoidCallback)>[
      (Icons.send_rounded, 'Envoyer', AppColors.violet, () => push(context, const SendScreen())),
      (Icons.qr_code_2_rounded, 'Recevoir', AppColors.indigo, () => push(context, const ReceiveScreen())),
      (Icons.storefront_rounded, 'Payer', AppColors.teal, () => push(context, const SendScreen(mode: SendMode.merchant))),
      (Icons.payments_outlined, 'Retrait', AppColors.amber, () => push(context, const SendScreen(mode: SendMode.agent))),
      (Icons.add_card_rounded, 'Dépôt', AppColors.green, () => push(context, const ReceiveScreen(deposit: true))),
      (Icons.request_quote_rounded, 'Prêts', AppColors.sky, () => push(context, const LoansScreen())),
      (Icons.event_available_rounded, 'Rembourser', const Color(0xFFDB2777), () => push(context, const RepaymentScreen())),
      (Icons.receipt_long_rounded, 'Historique', AppColors.navyLight, () => HomeShell.of(context)?.go(HomeShellState.tabHistory)),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        childAspectRatio: 0.86,
        children: [
          for (final (icon, label, color, onTap) in actions)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(icon, color: color, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
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
          IconBadge(Icons.event_available_rounded, color: color, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Prochaine échéance', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  installment.overdue
                      ? '${loan.productName} · en retard'
                      : '${loan.productName} · ${Fmt.shortDate(installment.dueDate)} (J-${days < 0 ? 0 : days})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ],
            ),
          ),
          MoneyText(
            installment.outstanding,
            currency: loan.currency,
            hidden: hidden,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
