import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../../state/session_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../accounts/accounts_screen.dart';
import '../loans/loan_detail_screen.dart';
import '../loans/repayment_screen.dart';
import '../profile/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/receive_screen.dart';
import '../wallet/send_screen.dart';
import 'home_shell.dart';

/// Accueil : solde centré, actions rondes, puis les dernières opérations.
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
    final next = bank.nextInstallment;
    final month = bank.monthlyStats(months: 1).first;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: bank.refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _Hero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (bank.error != null) ...[ErrorBanner(bank.error!, onRetry: bank.refresh), const SizedBox(height: 12)],
                  // Opérations récentes
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Column(
                      children: [
                        if (bank.history.isEmpty)
                          const EmptyState(icon: Icons.receipt_long_outlined, title: 'Aucune opération pour le moment')
                        else
                          for (final t in bank.history.take(4)) TransactionTile(t, hidden: hidden),
                        if (bank.history.isNotEmpty)
                          TextButton(
                            onPressed: () => HomeShell.of(context)?.go(HomeShellState.tabHistory),
                            child: const Text('Tout voir'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'Dépensé ce mois',
                          value: hidden ? '•••' : Fmt.money(month.expenses, currency: bank.currency),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          label: 'Reçu ce mois',
                          value: hidden ? '•••' : Fmt.money(month.income, currency: bank.currency),
                          positive: true,
                        ),
                      ),
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 12),
                    _NextInstallment(loan: next.$1, installment: next.$2, hidden: hidden),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau bleu nuit : profil, recherche, solde centré et 4 actions.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final session = context.watch<SessionController>();
    final client = bank.client!;
    final main = bank.savings.firstOrNull;
    final currency = main?.currency ?? bank.currency;
    final name = session.auth.fullName ?? client.displayName;
    final hidden = bank.balanceHidden;
    final amount = Fmt.money(main?.available ?? 0, currency: currency);
    final symbol = Fmt.symbol(currency);
    final number = amount.replaceAll(symbol, '').trim();

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => push(context, const ProfileScreen()),
                    child: Semantics(
                      button: true,
                      label: 'Profil',
                      excludeSemantics: true,
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                        child: Text(
                          Fmt.initials(name),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => HomeShell.of(context)?.go(HomeShellState.tabHistory),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: Colors.white70, size: 19),
                              SizedBox(width: 8),
                              Text('Rechercher', style: TextStyle(color: Colors.white70, fontSize: 14.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => push(context, const NotificationsScreen()),
                    icon: Badge(
                      isLabelVisible: bank.unreadCount > 0,
                      smallSize: 8,
                      backgroundColor: AppColors.gold,
                      child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Text('${main?.productName ?? 'Portefeuille'} · $symbol',
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: bank.toggleBalance,
                child: Semantics(
                  label: hidden ? 'Solde masqué, toucher pour afficher' : 'Solde $amount, toucher pour masquer',
                  excludeSemantics: true,
                  child: hidden
                      ? const Text('• • • • •',
                          style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700))
                      : Text.rich(
                          TextSpan(children: [
                            TextSpan(text: number),
                            TextSpan(
                              text: ' $symbol',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white70),
                            ),
                          ]),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.2,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.white.withValues(alpha: 0.14),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => push(context, const AccountsScreen()),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Comptes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundAction(icon: Icons.north_east_rounded, label: 'Envoyer', onTap: () => push(context, const SendScreen())),
                  _RoundAction(icon: Icons.south_west_rounded, label: 'Recevoir', onTap: () => push(context, const ReceiveScreen())),
                  _RoundAction(
                    icon: Icons.qr_code_2_rounded,
                    label: 'Payer',
                    onTap: () => push(context, const SendScreen(mode: SendMode.merchant)),
                  ),
                  _RoundAction(icon: Icons.more_horiz_rounded, label: 'Plus', onTap: () => showMoreActions(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille « Plus » : actions secondaires.
void showMoreActions(BuildContext context) {
  final items = <(IconData, String, String, VoidCallback)>[
    (Icons.payments_outlined, 'Retrait chez un agent', 'Espèces remises par un agent Golden Bridge',
        () => push(context, const SendScreen(mode: SendMode.agent))),
    (Icons.add_rounded, 'Déposer des espèces', 'Chez un agent ou en agence', () => push(context, const ReceiveScreen(deposit: true))),
    (Icons.event_available_outlined, 'Rembourser un prêt', 'Depuis votre portefeuille', () => push(context, const RepaymentScreen())),
    (Icons.account_balance_wallet_outlined, 'Mes comptes', 'Soldes et relevés', () => push(context, const AccountsScreen())),
  ];
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, title, subtitle, onTap) in items)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: IconBadge(icon),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(subtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  onTap();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.positive = false});
  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: positive ? AppColors.green : null),
              ),
            ),
          ],
        ),
      );
}

class _NextInstallment extends StatelessWidget {
  const _NextInstallment({required this.loan, required this.installment, required this.hidden});
  final LoanAccount loan;
  final Installment installment;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final days = installment.dueDate.difference(DateTime.now()).inDays;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SurfaceCard(
      onTap: () => push(context, LoanDetailScreen(loanId: loan.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(loan.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              MoneyText(
                installment.outstanding,
                currency: loan.currency,
                hidden: hidden,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            installment.overdue
                ? 'Échéance en retard'
                : 'Prochaine échéance le ${Fmt.date(installment.dueDate)} · dans ${days < 0 ? 0 : days} j',
            style: TextStyle(color: installment.overdue ? AppColors.red : muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: loan.progress,
              minHeight: 6,
              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
            ),
          ),
          const SizedBox(height: 6),
          Text('${(loan.progress * 100).round()} % remboursé', style: TextStyle(color: muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

