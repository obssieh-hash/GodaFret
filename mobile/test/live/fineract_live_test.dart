// Test d'intégration contre une vraie pile Fineract + Keycloak.
// Ignoré par défaut. Lancement (voir infra/README.md) :
//   LIVE_FINERACT=1 flutter test test/live
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_bridge_pay/config/app_config.dart';
import 'package:golden_bridge_pay/models/models.dart';
import 'package:golden_bridge_pay/services/api_client.dart';
import 'package:golden_bridge_pay/services/auth/keycloak_auth.dart';
import 'package:golden_bridge_pay/services/fineract_repository.dart';
import 'package:golden_bridge_pay/services/secure_store.dart';

class MemoryStore extends SecureStore {
  final _data = <String, String>{};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? _data.remove(key) : _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
  @override
  Future<void> clearSession() async => _data.clear();
}

void main() {
  final env = Platform.environment;
  final enabled = env['LIVE_FINERACT'] == '1';
  final config = AppConfig(
    authMode: AuthMode.keycloak,
    fineractUrl: env['FINERACT_URL'] ?? 'http://localhost:8082/fineract-provider/api/v1',
    tenant: 'default',
    keycloakUrl: env['KEYCLOAK_URL'] ?? 'http://localhost:8081',
    keycloakRealm: 'goldenbridge',
    keycloakClientId: 'gbpay-mobile',
    mfaRequired: false,
    currency: 'DJF',
    lockAfter: const Duration(seconds: 60),
  );

  late KeycloakAuthService auth;
  late FineractRepository repo;

  setUpAll(() async {
    if (!enabled) return;
    auth = KeycloakAuthService(config, MemoryStore());
    await auth.login(env['LIVE_USER'] ?? '77101010', env['LIVE_PASSWORD'] ?? 'Demo-Banque-2026');
    repo = FineractRepository(FineractApi(config, authHeaders: auth.authHeaders), auth);
  });

  test('parcours complet sur Fineract', () async {
    final client = await repo.loadClient();
    expect(client.displayName, 'Fatouma Ali Houssein');

    final accounts = await repo.accounts();
    expect(accounts.savings.length, greaterThanOrEqualTo(2));
    final wallet = accounts.savings.firstWhere((a) => a.productName == 'Portefeuille GB Pay');
    final epargne = accounts.savings.firstWhere((a) => a.id != wallet.id);
    expect(wallet.currency, 'DJF');
    final before = (await repo.savingsDetail(wallet.id)).account.balance;

    // Envoyer à un numéro de téléphone, payer un marchand, retirer chez un agent.
    final ahmed = await repo.findRecipient('+253 77 20 20 20');
    expect(ahmed.clientName, contains('Ahmed'));
    await repo.transfer(from: wallet, to: ahmed, amount: 2500, description: 'Envoi test');
    final shop = await repo.findRecipient('21350001');
    expect(shop.clientName, contains('Boulangerie'));
    await repo.transfer(from: wallet, to: shop, amount: 1500, description: 'Paiement test');
    final agent = await repo.findRecipient('77990001');
    expect(agent.clientName, contains('Agent'));
    await repo.transfer(from: wallet, to: agent, amount: 5000, description: 'Retrait test');
    // Vers mon épargne par numéro de compte.
    final own = await repo.findRecipient(epargne.accountNo);
    await repo.transfer(from: wallet, to: own, amount: 1000, description: 'Épargne');
    final detail = await repo.savingsDetail(wallet.id);
    expect(detail.account.balance, closeTo(before - 10000, 0.001));
    expect(() => repo.findRecipient('77000000'), throwsA(isA<ApiException>()));

    // Prêts : échéancier, simulation, demande, remboursement depuis le portefeuille.
    final active = accounts.loans.firstWhere((l) => l.state == LoanState.active);
    final loan = await repo.loanDetail(active.id);
    expect(loan.schedule, isNotEmpty);
    final products = await repo.loanProducts();
    expect(products, isNotEmpty);
    final p = products.first;
    final sim = await repo.simulateLoan(p, 200000, 12);
    expect(sim.installments, hasLength(12));
    expect(sim.totalRepayment, greaterThan(200000));
    await repo.applyForLoan(p, 200000, 12, purpose: 'Test intégration');
    expect((await repo.accounts()).loans.where((l) => l.state == LoanState.pending), isNotEmpty);

    final w = (await repo.savingsDetail(wallet.id)).account;
    await repo.repayLoan(active.id, 5000, from: w);
    final after = await repo.loanDetail(active.id);
    expect(after.outstanding, closeTo(loan.outstanding - 5000, 0.01));
    expect((await repo.savingsDetail(wallet.id)).account.balance, closeTo(w.balance - 5000, 0.001));

    final notifications = await repo.notifications();
    expect(notifications, isA<List<AppNotification>>());
  }, skip: enabled ? false : 'LIVE_FINERACT=1 requis', timeout: const Timeout(Duration(minutes: 3)));

  test('Fineract refuse les requêtes sans jeton', () async {
    final anonymous = FineractApi(config);
    expect(() => anonymous.get('/clients/1'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', 401)));
  }, skip: enabled ? false : 'LIVE_FINERACT=1 requis');
}
