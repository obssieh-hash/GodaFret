import 'package:flutter_test/flutter_test.dart';
import 'package:golden_bridge_pay/models/models.dart';
import 'package:golden_bridge_pay/services/api_client.dart';
import 'package:golden_bridge_pay/services/demo_repository.dart';

void main() {
  late DemoRepository repo;
  setUp(() => repo = DemoRepository());

  Future<SavingsAccount> wallet() async => (await repo.savingsDetail(101)).account;

  test('envoi à un numéro de téléphone', () async {
    final from = await wallet();
    final to = await repo.findRecipient('+253 77 20 20 20');
    expect(to.clientName, 'Ahmed Hassan Moussa');
    await repo.transfer(from: from, to: to, amount: 2500, description: '');
    expect((await wallet()).balance, closeTo(from.balance - 2500, 0.001));
  });

  test('paiement marchand et retrait agent par numéro', () async {
    expect((await repo.findRecipient('21350001')).clientName, contains('Boulangerie'));
    expect((await repo.findRecipient('77 99 00 01')).clientName, contains('Agent'));
  });

  test('transfert vers mon épargne par numéro de compte', () async {
    final from = await wallet();
    final before = (await repo.savingsDetail(102)).account.balance;
    final to = await repo.findRecipient('000000102');
    await repo.transfer(from: from, to: to, amount: 5000, description: '');
    expect((await repo.savingsDetail(102)).account.balance, closeTo(before + 5000, 0.001));
  });

  test('solde insuffisant', () async {
    final from = await wallet();
    final to = await repo.findRecipient('77202020');
    expect(() => repo.transfer(from: from, to: to, amount: 1e12, description: ''), throwsA(isA<ApiException>()));
  });

  test('numéro inconnu', () async {
    expect(() => repo.findRecipient('77000000'), throwsA(isA<ApiException>()));
  });

  test('demande de prêt puis remboursement depuis le portefeuille', () async {
    final products = await repo.loanProducts();
    await repo.applyForLoan(products.first, 200000, 12);
    expect((await repo.accounts()).loans.where((l) => l.state == LoanState.pending), hasLength(1));

    final loan = await repo.loanDetail(501);
    final next = loan.nextInstallment!;
    final before = (await wallet()).balance;
    await repo.repayLoan(501, next.outstanding, from: await wallet());
    final after = await repo.loanDetail(501);
    expect(after.outstanding, closeTo(loan.outstanding - next.outstanding, 0.01));
    expect(after.schedule.firstWhere((i) => i.number == next.number).complete, isTrue);
    expect((await wallet()).balance, closeTo(before - next.outstanding, 0.01));
  });

  test('montants en francs Djibouti entiers', () async {
    final loan = await repo.loanDetail(501);
    expect(loan.currency, 'DJF');
    expect(loan.schedule.every((i) => i.totalDue == i.totalDue.roundToDouble()), isTrue);
  });

  test('notifications lues', () async {
    expect((await repo.notifications()).any((n) => !n.read), isTrue);
    await repo.markNotificationsRead();
    expect((await repo.notifications()).every((n) => n.read), isTrue);
  });
}
