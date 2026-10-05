import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';

/// 💵 Remboursement d'un prêt (`POST /loans/{id}/transactions?command=repayment`).
class RepaymentScreen extends StatefulWidget {
  const RepaymentScreen({super.key, this.loanId});
  final int? loanId;

  @override
  State<RepaymentScreen> createState() => _RepaymentScreenState();
}

class _RepaymentScreenState extends State<RepaymentScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  LoanAccount? _loan;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final loans = context.read<BankController>().activeLoans;
    _choose(loans.where((l) => l.id == widget.loanId).firstOrNull ?? loans.firstOrNull);
  }

  void _choose(LoanAccount? loan) {
    _loan = loan;
    final next = loan?.nextInstallment;
    if (next != null) _amount.text = next.outstanding.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loan = _loan;
    if (loan == null || !_form.currentState!.validate()) return;
    final amount = AmountField.parse(_amount.text)!;
    final ok = await confirmWithPin(
      context,
      title: 'Confirmer le remboursement',
      summary: '${Fmt.money(amount, currency: loan.currency)} sur ${loan.productName}',
    );
    if (!ok || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<BankController>().perform((repo) => repo.repayLoan(loan.id, amount));
      if (!mounted) return;
      await SuccessScreen.show(
        context,
        title: 'Remboursement effectué',
        message: 'Votre paiement a été imputé sur votre prêt.',
        details: [
          ('Prêt', loan.productName),
          ('Montant', Fmt.money(amount, currency: loan.currency)),
          ('Restant dû', Fmt.money((loan.outstanding - amount).clamp(0, double.infinity), currency: loan.currency)),
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final loans = bank.activeLoans;
    final loan = _loan;
    if (loan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Remboursement')),
        body: const EmptyState(icon: Icons.celebration_rounded, title: 'Aucun prêt à rembourser', message: 'Vous êtes à jour 🎉'),
      );
    }
    final next = loan.nextInstallment;
    return Scaffold(
      appBar: AppBar(title: const Text('Remboursement')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            if (loans.length > 1) ...[
              const SectionHeader('Prêt'),
              Wrap(
                spacing: 8,
                children: [
                  for (final l in loans)
                    ChoiceChip(
                      label: Text(l.productName),
                      selected: l.id == loan.id,
                      onSelected: (_) => setState(() => _choose(l)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            GradientCard(
              gradient: AppColors.sunsetGradient,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loan.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  const Text('Restant dû', style: TextStyle(color: Colors.white70)),
                  Text(Fmt.money(loan.outstanding, currency: loan.currency),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  if (next != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Échéance n°${next.number} du ${Fmt.date(next.dueDate)} : ${Fmt.money(next.outstanding, currency: loan.currency)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            AmountField(
              controller: _amount,
              currency: loan.currency,
              validator: (v) {
                final a = AmountField.parse(v);
                if (a == null || a <= 0) return 'Saisissez un montant valide';
                if (a > loan.outstanding + 0.005) return 'Le montant dépasse le restant dû';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (next != null)
                  ActionChip(
                    avatar: const Icon(Icons.event_rounded, size: 18),
                    label: const Text('Échéance'),
                    onPressed: () => _amount.text = next.outstanding.toStringAsFixed(2).replaceAll('.', ','),
                  ),
                if (loan.overdue > 0)
                  ActionChip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Impayés'),
                    onPressed: () => _amount.text = loan.overdue.toStringAsFixed(2).replaceAll('.', ','),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Solder le prêt'),
                  onPressed: () => _amount.text = loan.outstanding.toStringAsFixed(2).replaceAll('.', ','),
                ),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(_error!)],
            const SizedBox(height: 26),
            PrimaryButton(label: 'Rembourser', icon: Icons.payments_rounded, loading: _sending, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
