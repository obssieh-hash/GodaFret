// Test d'intégration contre une vraie pile Fineract + Keycloak.
// Ignoré par défaut. Lancement (voir infra/README.md) :
//   LIVE_FINERACT=1 flutter test test/live
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:godafret_bank/config/app_config.dart';
import 'package:godafret_bank/models/models.dart';
import 'package:godafret_bank/services/api_client.dart';
import 'package:godafret_bank/services/auth/keycloak_auth.dart';
import 'package:godafret_bank/services/fineract_repository.dart';
import 'package:godafret_bank/services/secure_store.dart';

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
    keycloakRealm: 'godafret',
    keycloakClientId: 'godafret-mobile',
    mfaRequired: false,
    currency: 'EUR',
    lockAfter: const Duration(seconds: 60),
  );

  late KeycloakAuthService auth;
  late FineractRepository repo;

  setUpAll(() async {
    if (!enabled) return;
    auth = KeycloakAuthService(config, MemoryStore());
    await auth.login(env['LIVE_USER'] ?? 'camille', env['LIVE_PASSWORD'] ?? 'Demo-Banque-2026');
    repo = FineractRepository(FineractApi(config, authHeaders: auth.authHeaders), auth);
  });

  test('parcours complet sur Fineract', () async {
    final client = await repo.loadClient();
    expect(client.displayName, 'Camille Martin');

    final accounts = await repo.accounts();
    expect(accounts.savings.length, greaterThanOrEqualTo(2));
    final current = accounts.savings.firstWhere((a) => a.productName == 'Compte courant');
    final livret = accounts.savings.firstWhere((a) => a.productName != 'Compte courant');

    final before = (await repo.savingsDetail(current.id)).account.balance;
    final types = await repo.paymentTypes();
    await repo.deposit(current.id, 100, paymentTypeId: types.firstOrNull?.id, note: 'Test dépôt');
    await repo.withdraw(current.id, 40, paymentTypeId: types.firstOrNull?.id);
    final detail = await repo.savingsDetail(current.id);
    expect(detail.account.balance, closeTo(before + 60, 0.001));
    expect(detail.transactions.first.amount, -40);

    // Transfert vers mon livret puis vers un autre client.
    final own = await repo.findBeneficiary(livret.accountNo);
    await repo.transfer(from: current, to: own, amount: 10, description: 'Vers livret');
    final lucas = await repo.findBeneficiary(env['LIVE_BENEFICIARY'] ?? '000000003');
    expect(lucas.clientName, contains('Lucas'));
    await repo.transfer(from: current, to: lucas, amount: 5, description: 'Remboursement resto');
    expect((await repo.savingsDetail(current.id)).account.balance, closeTo(before + 45, 0.001));

    // Prêts : échéancier, simulation, demande, remboursement.
    final active = accounts.loans.firstWhere((l) => l.state == LoanState.active);
    final loan = await repo.loanDetail(active.id);
    expect(loan.schedule, isNotEmpty);
    final products = await repo.loanProducts();
    expect(products, isNotEmpty);
    final p = products.first;
    final sim = await repo.simulateLoan(p, 2000, 12);
    expect(sim.installments, hasLength(12));
    expect(sim.totalRepayment, greaterThan(2000));
    await repo.applyForLoan(p, 2000, 12, purpose: 'Test intégration');
    expect((await repo.accounts()).loans.where((l) => l.state == LoanState.pending), isNotEmpty);

    await repo.repayLoan(active.id, 50);
    final after = await repo.loanDetail(active.id);
    expect(after.outstanding, closeTo(loan.outstanding - 50, 0.01));

    final notifications = await repo.notifications();
    expect(notifications, isA<List<AppNotification>>());
  }, skip: enabled ? false : 'LIVE_FINERACT=1 requis', timeout: const Timeout(Duration(minutes: 3)));

  test('Fineract refuse les requêtes sans jeton', () async {
    final anonymous = FineractApi(config);
    expect(() => anonymous.get('/clients/1'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', 401)));
  }, skip: enabled ? false : 'LIVE_FINERACT=1 requis');
}
