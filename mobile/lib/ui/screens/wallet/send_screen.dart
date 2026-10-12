import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/brand.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';
import '../operations/account_picker.dart';

/// Les trois usages d'un même parcours « vers un autre compte Golden Bridge ».
enum SendMode { send, merchant, agent }

extension on SendMode {
  String get title => switch (this) {
        SendMode.send => "Envoyer de l'argent",
        SendMode.merchant => 'Payer un marchand',
        SendMode.agent => 'Retrait chez un agent',
      };
  String get fieldLabel => switch (this) {
        SendMode.send => 'Numéro du destinataire',
        SendMode.merchant => 'Numéro du marchand',
        SendMode.agent => "Numéro de l'agent",
      };
  String get action => switch (this) {
        SendMode.send => 'Envoyer',
        SendMode.merchant => 'Payer',
        SendMode.agent => 'Retirer',
      };
  IconData get icon => switch (this) {
        SendMode.send => Icons.send_rounded,
        SendMode.merchant => Icons.storefront_rounded,
        SendMode.agent => Icons.payments_outlined,
      };
  Color get color => switch (this) {
        SendMode.send => AppColors.violet,
        SendMode.merchant => AppColors.teal,
        SendMode.agent => AppColors.amber,
      };
  String label(String name) => switch (this) {
        SendMode.send => 'Envoi à $name',
        SendMode.merchant => 'Paiement $name',
        SendMode.agent => 'Retrait chez $name',
      };
}

/// 💸 Envoyer / payer / retirer chez un agent : numéro → montant → PIN → reçu.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.mode = SendMode.send, this.prefill});

  final SendMode mode;
  final String? prefill;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.prefill ?? '');
  final _amount = TextEditingController();
  final _note = TextEditingController();
  SavingsAccount? _from;
  Beneficiary? _to;
  bool _searching = false;
  bool _sending = false;
  String? _error;

  SendMode get mode => widget.mode;

  @override
  void initState() {
    super.initState();
    _from = context.read<BankController>().savings.firstOrNull;
    if (widget.prefill != null) WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
  }

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final q = _number.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _to = null;
    });
    try {
      final b = await context.read<BankController>().repo.findRecipient(q);
      if (mounted) setState(() => _to = b);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    final from = _from;
    final to = _to;
    if (to == null) {
      await _lookup();
      return;
    }
    if (from == null || !_form.currentState!.validate()) return;
    if (to.accountId == from.id) {
      setState(() => _error = 'Vous ne pouvez pas vous envoyer de l\'argent sur le même compte.');
      return;
    }
    final amount = AmountField.parse(_amount.text)!;
    final money = Fmt.money(amount, currency: from.currency);
    final ok = await confirmWithPin(context, title: '${mode.action} $money', summary: '${mode.label(to.clientName)}\nFrais : 0 Fdj');
    if (!ok || !mounted) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    final note = _note.text.trim();
    final description = note.isEmpty ? mode.label(to.clientName) : '${mode.label(to.clientName)} · $note';
    try {
      await context.read<BankController>().perform(
            (repo) => repo.transfer(from: from, to: to, amount: amount, description: description),
          );
      if (!mounted) return;
      await SuccessScreen.show(
        context,
        title: switch (mode) {
          SendMode.send => 'Argent envoyé',
          SendMode.merchant => 'Paiement effectué',
          SendMode.agent => 'Retrait validé',
        },
        message: mode == SendMode.agent
            ? "Montrez cet écran à l'agent : il vous remet $money en espèces."
            : '${to.clientName} a reçu $money instantanément.',
        details: [
          ('Montant', money),
          (mode == SendMode.send ? 'Destinataire' : (mode == SendMode.merchant ? 'Marchand' : 'Agent'), to.clientName),
          if (to.phone != null) ('Numéro', Fmt.phone(to.phone)),
          ('Frais', '0 Fdj'),
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
    final scheme = Theme.of(context).colorScheme;
    final currency = _from?.currency ?? bank.currency;
    return Scaffold(
      appBar: AppBar(title: Text(mode.title)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            // 1. Destinataire
            TextField(
              controller: _number,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.search,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
              onSubmitted: (_) => _lookup(),
              onChanged: (_) {
                if (_to != null) setState(() => _to = null);
              },
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1),
              decoration: InputDecoration(
                labelText: mode.fieldLabel,
                hintText: '77 00 00 00',
                prefixIcon: Icon(mode.icon, color: mode.color),
                prefixText: '${Brand.phonePrefix} ',
                helperText: 'Ou numéro de compte Golden Bridge',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(tooltip: 'Vérifier', onPressed: _lookup, icon: const Icon(Icons.arrow_forward_rounded)),
              ),
            ),
            if (_to != null) ...[
              const SizedBox(height: 12),
              _RecipientCard(recipient: _to!, mode: mode),
            ],
            if (_to != null) ...[
              const SizedBox(height: 22),
              // 2. Montant
              AmountField(
                controller: _amount,
                currency: currency,
                autofocus: true,
                validator: (v) {
                  final a = AmountField.parse(v);
                  if (a == null || a <= 0) return 'Saisissez un montant';
                  if (_from != null && a > _from!.available) {
                    return 'Solde insuffisant (${Fmt.money(_from!.available, currency: currency)})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final v in const [1000, 2000, 5000, 10000, 20000])
                    ActionChip(
                      label: Text(Fmt.money(v, currency: currency)),
                      onPressed: () => _amount.text = '$v',
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (bank.savings.length > 1)
                AccountPicker(
                  label: 'Depuis',
                  accounts: bank.savings,
                  selected: _from,
                  hidden: bank.balanceHidden,
                  onChanged: (a) => setState(() => _from = a),
                )
              else if (_from != null)
                Text(
                  'Depuis ${_from!.productName} · solde ${bank.balanceHidden ? '•••' : Fmt.money(_from!.available, currency: currency)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              if (mode == SendMode.send) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Motif (facultatif)', prefixIcon: Icon(Icons.short_text_rounded)),
                ),
              ],
              if (mode == SendMode.agent) ...[
                const SizedBox(height: 14),
                const InfoBanner(
                  "Validez le retrait devant l'agent : il vous remet les espèces dès qu'il voit le reçu.",
                  icon: Icons.storefront_outlined,
                ),
              ],
            ],
            if (_error != null) ...[const SizedBox(height: 14), ErrorBanner(_error!)],
            const SizedBox(height: 22),
            PrimaryButton(
              label: _to == null ? 'Vérifier le numéro' : mode.action,
              icon: _to == null ? Icons.search_rounded : mode.icon,
              loading: _sending || _searching,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({required this.recipient, required this.mode});
  final Beneficiary recipient;
  final SendMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Avatar(recipient.clientName, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipient.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                Text(
                  [
                    if (recipient.phone != null) Fmt.phone(recipient.phone),
                    'Compte ${Fmt.maskAccount(recipient.accountNo)}',
                  ].join(' · '),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: AppColors.green),
        ],
      ),
    );
  }
}
