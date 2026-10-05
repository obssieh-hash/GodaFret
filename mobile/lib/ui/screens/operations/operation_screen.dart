import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';
import 'account_picker.dart';

enum OperationType { deposit, withdrawal }

/// ➕ Dépôt / ➖ Retrait sur un compte épargne Fineract.
class OperationScreen extends StatefulWidget {
  const OperationScreen({super.key, required this.type, this.accountId});

  final OperationType type;
  final int? accountId;

  @override
  State<OperationScreen> createState() => _OperationScreenState();
}

class _OperationScreenState extends State<OperationScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  SavingsAccount? _account;
  List<PaymentType> _paymentTypes = const [];
  PaymentType? _paymentType;
  bool _sending = false;
  String? _error;

  bool get _isDeposit => widget.type == OperationType.deposit;

  @override
  void initState() {
    super.initState();
    final bank = context.read<BankController>();
    final accounts = bank.savings;
    _account = accounts.where((a) => a.id == widget.accountId).firstOrNull ?? accounts.firstOrNull;
    bank.repo.paymentTypes().then((types) {
      if (!mounted) return;
      setState(() {
        _paymentTypes = types;
        _paymentType = types.firstOrNull;
      });
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _account == null) return;
    final amount = AmountField.parse(_amount.text)!;
    final account = _account!;
    final label = _isDeposit ? 'dépôt' : 'retrait';

    if (!_isDeposit) {
      final ok = await confirmWithPin(
        context,
        title: 'Confirmer le retrait',
        summary: '${Fmt.money(amount, currency: account.currency)} depuis ${account.productName}',
      );
      if (!ok || !mounted) return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<BankController>().perform((repo) => _isDeposit
          ? repo.deposit(account.id, amount, paymentTypeId: _paymentType?.id, note: _note.text.trim())
          : repo.withdraw(account.id, amount, paymentTypeId: _paymentType?.id, note: _note.text.trim()));
      if (!mounted) return;
      await SuccessScreen.show(
        context,
        title: _isDeposit ? 'Dépôt effectué' : 'Retrait effectué',
        message: 'Votre $label a été enregistré.',
        details: [
          ('Montant', Fmt.money(amount, currency: account.currency)),
          ('Compte', account.productName),
          if (_paymentType != null) ('Moyen', _paymentType!.name),
          ('Date', Fmt.date(DateTime.now())),
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
    final color = _isDeposit ? AppColors.green : AppColors.red;
    return Scaffold(
      appBar: AppBar(title: Text(_isDeposit ? 'Faire un dépôt' : 'Faire un retrait')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Center(child: IconBadge(_isDeposit ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 64)),
            const SizedBox(height: 18),
            AmountField(
              controller: _amount,
              currency: _account?.currency ?? bank.currency,
              autofocus: true,
              validator: (v) {
                final a = AmountField.parse(v);
                if (a == null || a <= 0) return 'Saisissez un montant valide';
                if (!_isDeposit && _account != null && a > _account!.available) {
                  return 'Solde disponible insuffisant (${Fmt.money(_account!.available, currency: _account!.currency)})';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final v in const [20, 50, 100, 200, 500])
                  ActionChip(
                    label: Text(Fmt.money(v, currency: _account?.currency ?? bank.currency).replaceAll(',00', '')),
                    onPressed: () => _amount.text = '$v',
                  ),
              ],
            ),
            const SizedBox(height: 22),
            AccountPicker(
              label: _isDeposit ? 'Créditer le compte' : 'Débiter le compte',
              accounts: bank.savings,
              selected: _account,
              hidden: bank.balanceHidden,
              onChanged: (a) => setState(() => _account = a),
            ),
            if (_paymentTypes.isNotEmpty) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(_isDeposit ? 'Moyen de dépôt' : 'Moyen de retrait',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _paymentTypes)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: _paymentType?.id == p.id,
                      onSelected: (_) => setState(() => _paymentType = p),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Libellé (facultatif)', prefixIcon: Icon(Icons.edit_note_rounded)),
            ),
            if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(_error!)],
            const SizedBox(height: 26),
            PrimaryButton(
              label: _isDeposit ? 'Déposer' : 'Retirer',
              icon: _isDeposit ? Icons.add_rounded : Icons.remove_rounded,
              loading: _sending,
              onPressed: _account == null ? null : _submit,
            ),
            if (!_isDeposit) ...[
              const SizedBox(height: 12),
              const InfoBanner('Les retraits sont confirmés par votre code PIN.', icon: Icons.lock_outline_rounded),
            ],
          ],
        ),
      ),
    );
  }
}
