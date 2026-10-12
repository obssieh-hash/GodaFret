import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/brand.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm.dart';

/// Les trois usages d'un même parcours « vers un autre compte Golden Bridge ».
enum SendMode { send, merchant, agent }

extension on SendMode {
  String get title => switch (this) {
        SendMode.send => "Envoyer de l'argent",
        SendMode.merchant => 'Payer un marchand',
        SendMode.agent => 'Retrait chez un agent',
      };
  String get question => switch (this) {
        SendMode.send => 'À qui envoyez-vous ?',
        SendMode.merchant => 'Quel marchand payez-vous ?',
        SendMode.agent => 'Chez quel agent retirez-vous ?',
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
  String label(String name) => switch (this) {
        SendMode.send => 'Envoi à $name',
        SendMode.merchant => 'Paiement $name',
        SendMode.agent => 'Retrait chez $name',
      };
}

/// 💸 Envoyer / payer / retirer chez un agent :
/// 1. numéro du destinataire, 2. montant au pavé numérique, 3. PIN, 4. reçu.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.mode = SendMode.send, this.prefill});

  final SendMode mode;
  final String? prefill;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  late final _number = TextEditingController(text: widget.prefill ?? '');
  final _note = TextEditingController();
  String _amount = '';
  SavingsAccount? _from;
  Beneficiary? _to;
  bool _searching = false;
  bool _sending = false;
  String? _error;

  SendMode get mode => widget.mode;
  double get _value => double.tryParse(_amount) ?? 0;

  @override
  void initState() {
    super.initState();
    _from = context.read<BankController>().savings.firstOrNull;
    if (widget.prefill != null) WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
  }

  @override
  void dispose() {
    _number.dispose();
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
    });
    try {
      final b = await context.read<BankController>().repo.findRecipient(q);
      if (!mounted) return;
      if (b.accountId == _from?.id) {
        setState(() => _error = 'Vous ne pouvez pas vous envoyer de l\'argent sur le même compte.');
      } else {
        setState(() => _to = b);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _key(String k) {
    final next = (_amount + k).replaceFirst(RegExp(r'^0+'), '');
    if (next.length > 9) return;
    setState(() {
      _amount = next;
      _error = null;
    });
  }

  void _delete() {
    if (_amount.isEmpty) return;
    setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  Future<void> _submit() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null || _value <= 0) return;
    if (_value > from.available) {
      setState(() => _error = 'Solde insuffisant (${Fmt.money(from.available, currency: from.currency)}).');
      return;
    }
    final amount = _value;
    final money = Fmt.money(amount, currency: from.currency);
    final ok = await confirmWithPin(context, title: '${mode.action} $money', summary: '${mode.label(to.clientName)}\nSans frais');
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
        amount: money,
        message: mode == SendMode.agent
            ? "Montrez cet écran à l'agent : il vous remet les espèces."
            : 'à ${to.clientName}',
        details: [
          (mode == SendMode.send ? 'Destinataire' : (mode == SendMode.merchant ? 'Marchand' : 'Agent'), to.clientName),
          if (to.phone != null) ('Numéro', Fmt.phone(to.phone)),
          ('Depuis', from.productName),
          ('Frais', '0 ${Fmt.symbol(from.currency)}'),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(mode.title),
        leading: _to == null
            ? null
            : IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _to = null;
                  _amount = '';
                }),
              ),
      ),
      body: SafeArea(top: false, child: _to == null ? _recipientStep(context) : _amountStep(context)),
    );
  }

  // Étape 1 : destinataire
  Widget _recipientStep(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(mode.question, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 20),
          TextField(
            controller: _number,
            autofocus: widget.prefill == null,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.search,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
            onSubmitted: (_) => _lookup(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0.5),
            decoration: InputDecoration(
              labelText: mode.fieldLabel,
              hintText: '77 00 00 00',
              prefixText: '${Brand.phonePrefix}  ',
              helperText: 'Ou numéro de compte Golden Bridge',
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 14), ErrorBanner(_error!)],
          const Spacer(),
          if (mode == SendMode.agent)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: InfoBanner("Validez le retrait devant l'agent : il vous remet les espèces dès qu'il voit le reçu."),
            ),
          PrimaryButton(label: 'Continuer', loading: _searching, onPressed: _lookup),
        ],
      ),
    );
  }

  // Étape 2 : montant
  Widget _amountStep(BuildContext context) {
    final bank = context.watch<BankController>();
    final scheme = Theme.of(context).colorScheme;
    final to = _to!;
    final from = _from;
    final currency = from?.currency ?? bank.currency;
    final symbol = Fmt.symbol(currency);
    final shown = _value == 0 ? '0' : Fmt.money(_value, currency: currency).replaceAll(symbol, '').trim();
    final tooMuch = from != null && _value > from.available;

    return Column(
      children: [
        const SizedBox(height: 4),
        Avatar(to.clientName, size: 52),
        const SizedBox(height: 8),
        Text(to.clientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        if (to.phone != null)
          Text('${Brand.phonePrefix} ${Fmt.phone(to.phone)}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: shown),
                      TextSpan(text: ' $symbol', style: TextStyle(fontSize: 26, color: scheme.onSurfaceVariant)),
                    ]),
                    semanticsLabel: 'Montant $shown $symbol',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      color: tooMuch ? AppColors.red : (_value == 0 ? scheme.onSurfaceVariant : scheme.onSurface),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (bank.savings.length > 1)
                  TextButton.icon(
                    onPressed: () => _pickAccount(context, bank),
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    label: Text(
                      '${from?.productName ?? ''} · ${bank.balanceHidden ? '•••' : Fmt.money(from?.available ?? 0, currency: currency)}',
                    ),
                  )
                else
                  Text(
                    'Solde : ${bank.balanceHidden ? '•••' : Fmt.money(from?.available ?? 0, currency: currency)}',
                    style: TextStyle(color: tooMuch ? AppColors.red : scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        if (mode == SendMode.send)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _note,
              maxLength: 60,
              decoration: const InputDecoration(hintText: 'Ajouter un motif (facultatif)', counterText: ''),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0), child: ErrorBanner(_error!)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: AmountKeypad(
            onKey: _key,
            onDelete: _delete,
            extraKey: Fmt.decimals(currency) == 0 ? '000' : '00',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: PrimaryButton(
            label: _value == 0 ? mode.action : '${mode.action} ${Fmt.money(_value, currency: currency)}',
            loading: _sending,
            onPressed: _value == 0 || tooMuch ? null : _submit,
          ),
        ),
      ],
    );
  }

  void _pickAccount(BuildContext context, BankController bank) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in bank.savings)
              ListTile(
                leading: const IconBadge(Icons.account_balance_wallet_outlined),
                title: Text(a.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(Fmt.maskAccount(a.accountNo)),
                trailing: a.id == _from?.id
                    ? const Icon(Icons.check_rounded)
                    : MoneyText(a.available, currency: a.currency, hidden: bank.balanceHidden),
                onTap: () {
                  setState(() => _from = a);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
