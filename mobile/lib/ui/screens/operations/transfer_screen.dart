import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';
import 'account_picker.dart';

/// 💸 Transfert interne : entre ses comptes ou vers un autre client de la banque.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, this.fromAccountId});
  final int? fromAccountId;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _accountNo = TextEditingController();
  final _description = TextEditingController();
  SavingsAccount? _from;
  Beneficiary? _to;
  bool _ownAccounts = true;
  bool _searching = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final accounts = context.read<BankController>().savings;
    _from = accounts.where((a) => a.id == widget.fromAccountId).firstOrNull ?? accounts.firstOrNull;
    _ownAccounts = accounts.length > 1;
  }

  @override
  void dispose() {
    _amount.dispose();
    _accountNo.dispose();
    _description.dispose();
    super.dispose();
  }

  Beneficiary _ownBeneficiary(SavingsAccount a) {
    final bank = context.read<BankController>();
    return Beneficiary(
      accountId: a.id,
      accountNo: a.accountNo,
      clientId: bank.client!.id,
      clientName: a.productName,
      officeId: bank.client!.officeId ?? 1,
    );
  }

  Future<void> _lookup() async {
    final no = _accountNo.text.trim();
    if (no.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _to = null;
    });
    try {
      final b = await context.read<BankController>().repo.findBeneficiary(no);
      if (mounted) setState(() => _to = b);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      setState(() => _error = 'Choisissez le bénéficiaire.');
      return;
    }
    if (to.accountId == from.id) {
      setState(() => _error = 'Les comptes de départ et d\'arrivée doivent être différents.');
      return;
    }
    final amount = AmountField.parse(_amount.text)!;
    final ok = await confirmWithPin(
      context,
      title: 'Confirmer le transfert',
      summary: '${Fmt.money(amount, currency: from.currency)} vers ${to.clientName}',
    );
    if (!ok || !mounted) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<BankController>().perform(
            (repo) => repo.transfer(from: from, to: to, amount: amount, description: _description.text.trim()),
          );
      if (!mounted) return;
      await SuccessScreen.show(
        context,
        title: 'Transfert envoyé',
        message: 'Les fonds ont été transférés instantanément.',
        details: [
          ('Montant', Fmt.money(amount, currency: from.currency)),
          ('De', from.productName),
          ('Vers', to.clientName),
          ('Compte', Fmt.maskAccount(to.accountNo)),
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
    final others = bank.savings.where((a) => a.id != _from?.id).toList();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfert interne')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            AccountPicker(
              label: 'Depuis',
              accounts: bank.savings,
              selected: _from,
              hidden: bank.balanceHidden,
              onChanged: (a) => setState(() {
                _from = a;
                if (_to?.accountId == a.id) _to = null;
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Vers', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Mes comptes'), icon: Icon(Icons.person_rounded)),
                ButtonSegment(value: false, label: Text('Un bénéficiaire'), icon: Icon(Icons.group_rounded)),
              ],
              selected: {_ownAccounts},
              onSelectionChanged: (s) => setState(() {
                _ownAccounts = s.first;
                _to = null;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_ownAccounts)
              others.isEmpty
                  ? const InfoBanner('Vous n\'avez pas d\'autre compte. Choisissez « Un bénéficiaire ».')
                  : Column(
                      children: [
                        for (final a in others)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SelectableTile(
                              selected: _to?.accountId == a.id,
                              icon: Icons.savings_rounded,
                              title: a.productName,
                              subtitle: Fmt.maskAccount(a.accountNo),
                              onTap: () => setState(() => _to = _ownBeneficiary(a)),
                            ),
                          ),
                      ],
                    )
            else ...[
              TextField(
                controller: _accountNo,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookup(),
                decoration: InputDecoration(
                  labelText: 'Numéro de compte du bénéficiaire',
                  prefixIcon: const Icon(Icons.numbers_rounded),
                  suffixIcon: _searching
                      ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(onPressed: _lookup, icon: const Icon(Icons.search_rounded)),
                ),
              ),
              if (_to != null) ...[
                const SizedBox(height: 10),
                _SelectableTile(
                  selected: true,
                  icon: Icons.verified_rounded,
                  title: _to!.clientName,
                  subtitle: 'Compte ${Fmt.maskAccount(_to!.accountNo)} · vérifié',
                  onTap: () {},
                ),
              ],
            ],
            const SizedBox(height: 22),
            AmountField(
              controller: _amount,
              currency: _from?.currency ?? bank.currency,
              validator: (v) {
                final a = AmountField.parse(v);
                if (a == null || a <= 0) return 'Saisissez un montant valide';
                if (_from != null && a > _from!.available) return 'Solde insuffisant';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Motif (facultatif)', prefixIcon: Icon(Icons.short_text_rounded)),
            ),
            if (_error != null) ...[const SizedBox(height: 8), ErrorBanner(_error!)],
            const SizedBox(height: 20),
            PrimaryButton(label: 'Transférer', icon: Icons.send_rounded, loading: _sending, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 1.6),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          leading: IconBadge(icon, color: AppColors.violet),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: selected ? Icon(Icons.check_circle_rounded, color: scheme.primary) : null,
        ),
      ),
    );
  }
}
