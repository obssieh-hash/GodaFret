import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../widgets/common.dart';

/// Carte de sélection d'un compte (ouvre une feuille de choix).
class AccountPicker extends StatelessWidget {
  const AccountPicker({
    super.key,
    required this.label,
    required this.accounts,
    required this.selected,
    required this.onChanged,
    this.hidden = false,
  });

  final String label;
  final List<SavingsAccount> accounts;
  final SavingsAccount? selected;
  final ValueChanged<SavingsAccount> onChanged;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        ),
        SurfaceCard(
          onTap: accounts.length < 2 ? null : () => _pick(context),
          child: a == null
              ? const Text('Aucun compte disponible')
              : Row(
                  children: [
                    const IconBadge(Icons.account_balance_wallet_rounded, color: AppColors.indigo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(Fmt.maskAccount(a.accountNo), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ),
                    MoneyText(a.balance, currency: a.currency, hidden: hidden, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (accounts.length > 1) const Icon(Icons.expand_more_rounded),
                  ],
                ),
        ),
      ],
    );
  }

  void _pick(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text('Choisir un compte', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            for (final a in accounts)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const IconBadge(Icons.account_balance_wallet_rounded, color: AppColors.indigo),
                title: Text(a.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(Fmt.maskAccount(a.accountNo)),
                trailing: a.id == selected?.id
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.green)
                    : MoneyText(a.balance, currency: a.currency, hidden: hidden),
                onTap: () {
                  onChanged(a);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}
