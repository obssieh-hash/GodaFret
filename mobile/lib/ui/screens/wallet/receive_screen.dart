import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/brand.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/bank_controller.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';

/// 📥 Recevoir de l'argent / déposer des espèces chez un agent :
/// le client montre son numéro ou son QR code.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key, this.deposit = false});

  /// `true` : écran « Dépôt » (espèces remises à un agent ou en agence).
  final bool deposit;

  @override
  Widget build(BuildContext context) {
    final bank = context.watch<BankController>();
    final client = bank.client;
    final account = bank.savings.firstOrNull;
    if (client == null || account == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.qr_code_2_rounded, title: 'Aucun compte actif'));
    }
    final phone = client.mobileNo ?? '';
    final payload = 'GBPAY|${normalizePhone(phone)}|${account.accountNo}|${client.displayName}';

    void copy(String text, String what) {
      Clipboard.setData(ClipboardData(text: text));
      showSnack(context, '$what copié');
    }

    return Scaffold(
      appBar: AppBar(title: Text(deposit ? 'Déposer des espèces' : 'Recevoir de l\'argent')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(28)),
            child: Column(
              children: [
                const BrandWordmark(onDark: true, size: 18),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                  child: QrImageView(
                    data: payload,
                    size: 210,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: AppColors.navy),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: AppColors.navy),
                    semanticsLabel: 'QR code de ${client.displayName}',
                  ),
                ),
                const SizedBox(height: 16),
                Text(client.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 4),
                Text(
                  '${Brand.phonePrefix} ${Fmt.phone(phone)}',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const IconBadge(Icons.phone_iphone_rounded, color: AppColors.indigo, size: 40),
                  title: const Text('Mon numéro'),
                  subtitle: Text(Fmt.phone(phone), style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: IconButton(
                    tooltip: 'Copier le numéro',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => copy(normalizePhone(phone), 'Numéro'),
                  ),
                ),
                ListTile(
                  leading: const IconBadge(Icons.account_balance_wallet_rounded, color: AppColors.amber, size: 40),
                  title: Text(account.productName),
                  subtitle: Text('N° ${account.accountNo}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: IconButton(
                    tooltip: 'Copier le numéro de compte',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => copy(account.accountNo, 'Numéro de compte'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InfoBanner(
            deposit
                ? "Remettez vos espèces à un agent Golden Bridge ou au guichet d'une agence en donnant ce numéro "
                    '(ou en montrant le QR code). Le dépôt apparaît aussitôt sur votre solde.'
                : 'Donnez ce numéro à la personne qui vous envoie de l\'argent : elle le saisit dans « Envoyer ». '
                    'Les fonds arrivent instantanément.',
            icon: deposit ? Icons.store_mall_directory_outlined : Icons.info_outline_rounded,
          ),
        ],
      ),
    );
  }
}
