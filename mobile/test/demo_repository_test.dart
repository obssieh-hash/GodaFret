import 'package:flutter_test/flutter_test.dart';
import 'package:godafret_bank/models/models.dart';
import 'package:godafret_bank/services/api_client.dart';
import 'package:godafret_bank/services/demo_repository.dart';

void main() {
  late DemoRepository repo;
  setUp(() => repo = DemoRepository());

  Future<double> balance(int id) async => (await repo.savingsDetail(id)).account.balance;

  test('dépôt puis retrait', () async {
    final start = await balance(101);
    await repo.deposit(101, 100);
    expect(await balance(101), closeTo(start + 100, 0.001));
    await repo.withdraw(101, 30);
    expect(await balance(101), closeTo(start + 70, 0.001));
  });

  test('retrait refusé si solde insuffisant', () async {
    expect(() => repo.withdraw(101, 1e9), throwsA(isA<ApiException>()));
  });

  test('transfert interne entre mes comptes', () async {
    final a = await balance(101);
    final b = await balance(102);
    final from = (await repo.savingsDetail(101)).account;
    final to = await repo.findBeneficiary('000000102');
    await repo.transfer(from: from, to: to, amount: 50, description: '');
    expect(await balance(101), closeTo(a - 50, 0.001));
    expect(await balance(102), closeTo(b + 50, 0.001));
  });

  test('bénéficiaire inconnu', () async {
    expect(() => repo.findBeneficiary('999'), throwsA(isA<ApiException>()));
  });

  test('demande de prêt en attente puis remboursement', () async {
    final products = await repo.loanProducts();
    await repo.applyForLoan(products.first, 2000, 12);
    final accounts = await repo.accounts();
    expect(accounts.loans.where((l) => l.state == LoanState.pending), hasLength(1));

    final loan = await repo.loanDetail(501);
    final next = loan.nextInstallment!;
    await repo.repayLoan(501, next.outstanding);
    final after = await repo.loanDetail(501);
    expect(after.outstanding, closeTo(loan.outstanding - next.outstanding, 0.01));
    expect(after.schedule.firstWhere((i) => i.number == next.number).complete, isTrue);
  });

  test('notifications lues', () async {
    expect((await repo.notifications()).any((n) => !n.read), isTrue);
    await repo.markNotificationsRead();
    expect((await repo.notifications()).every((n) => n.read), isTrue);
  });
}
