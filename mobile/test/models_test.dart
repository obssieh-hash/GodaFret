import 'package:flutter_test/flutter_test.dart';
import 'package:godafret_bank/core/formatters.dart';
import 'package:godafret_bank/models/models.dart';
import 'package:godafret_bank/services/api_client.dart';
import 'package:godafret_bank/services/auth/keycloak_auth.dart';
import 'package:godafret_bank/services/demo_repository.dart';
import 'package:godafret_bank/services/pin_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Dates Fineract', () {
    test('tableau [a, m, j]', () {
      expect(Fmt.parseFineract([2026, 10, 5]), DateTime(2026, 10, 5));
    });
    test('chaîne ISO', () {
      expect(Fmt.parseFineract('2026-01-31'), DateTime(2026, 1, 31));
    });
    test('null', () => expect(Fmt.parseFineract(null), isNull));
    test('format API', () => expect(Fmt.api(DateTime(2026, 3, 7)), '2026-03-07'));
  });

  test('montants au format français', () {
    expect(Fmt.money(1234.5).replaceAll(RegExp('[\u00a0\u202f]'), ' '), '1 234,50 €');
    expect(Fmt.money(-20, signed: true), startsWith('−'));
    expect(Fmt.maskAccount('000000101'), '•••• 0101');
    expect(Fmt.initials('Camille Martin'), 'CM');
  });

  test('compte épargne depuis GET /savingsaccounts/{id}', () {
    final a = SavingsAccount.fromDetail({
      'id': 7,
      'accountNo': '000000007',
      'savingsProductName': 'Épargne',
      'clientId': 3,
      'currency': {'code': 'XOF'},
      'status': {'active': true, 'value': 'Active'},
      'summary': {'accountBalance': 1500.25, 'availableBalance': 1400},
    });
    expect(a.balance, 1500.25);
    expect(a.available, 1400);
    expect(a.currency, 'XOF');
  });

  test('transaction épargne : un retrait est négatif, un virement entrant est un transfert', () {
    final w = BankTransaction.fromSavingsJson({
      'id': 1,
      'transactionType': {'withdrawal': true, 'value': 'Withdrawal'},
      'date': [2026, 9, 1],
      'amount': 40,
    }, accountId: 7, currency: 'EUR');
    expect(w.amount, -40);
    expect(w.kind, TxKind.withdrawal);

    final t = BankTransaction.fromSavingsJson({
      'id': 2,
      'transactionType': {'deposit': true, 'value': 'Deposit'},
      'transfer': {'id': 9},
      'date': [2026, 9, 2],
      'amount': 15,
    }, accountId: 7, currency: 'EUR');
    expect(t.kind, TxKind.transferIn);
    expect(t.amount, 15);
  });

  test('prêt : échéancier sans la période 0 (décaissement)', () {
    final l = LoanAccount.fromDetail({
      'id': 4,
      'accountNo': '0004',
      'loanProductName': 'Microcrédit',
      'principal': 1000,
      'currency': {'code': 'EUR'},
      'status': {'active': true, 'value': 'Active'},
      'summary': {'totalOutstanding': 800, 'totalRepayment': 210, 'totalOverdue': 0},
      'repaymentSchedule': {
        'periods': [
          {'dueDate': [2026, 1, 1], 'principalDisbursed': 1000},
          {'period': 1, 'dueDate': [2026, 2, 1], 'principalDue': 200, 'interestDue': 10, 'totalDueForPeriod': 210, 'totalPaidForPeriod': 210, 'totalOutstandingForPeriod': 0, 'complete': true},
          {'period': 2, 'dueDate': [2026, 3, 1], 'principalDue': 200, 'interestDue': 8, 'totalDueForPeriod': 208, 'totalPaidForPeriod': 0, 'totalOutstandingForPeriod': 208, 'complete': false},
        ],
      },
      'transactions': [
        {'id': 1, 'type': {'disbursement': true, 'value': 'Disbursement'}, 'date': [2026, 1, 1], 'amount': 1000},
        {'id': 2, 'type': {'repayment': true, 'value': 'Repayment'}, 'date': [2026, 2, 1], 'amount': 210},
      ],
    });
    expect(l.state, LoanState.active);
    expect(l.schedule, hasLength(2));
    expect(l.nextInstallment!.number, 2);
    expect(l.transactions.last.amount, -210);
  });

  test('amortissement : mensualités constantes et capital entièrement remboursé', () {
    final s = DemoRepository.amortize(12000, 24, 0.005, DateTime(2026, 1, 1));
    expect(s, hasLength(24));
    final principal = s.fold<double>(0, (a, i) => a + i.principal);
    expect(principal, closeTo(12000, 0.01));
    expect(s.first.totalDue, closeTo(s[10].totalDue, 0.01));
  });

  test('PIN : refuse les codes triviaux', () {
    expect(PinService.validateNewPin('123456'), isNotNull);
    expect(PinService.validateNewPin('000000'), isNotNull);
    expect(PinService.validateNewPin('987654'), isNotNull);
    expect(PinService.validateNewPin('12345'), isNotNull);
    expect(PinService.validateNewPin('274913'), isNull);
  });

  test('JWT Keycloak : lecture du claim fineract_client_id', () {
    String enc(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final token = '${enc({'alg': 'RS256'})}.${enc({'preferred_username': 'camille', 'fineract_client_id': '12'})}.sig';
    final claims = KeycloakAuthService.decodeJwt(token);
    expect(claims['preferred_username'], 'camille');
    expect(claims['fineract_client_id'], '12');
  });

  test('erreurs Fineract et Keycloak traduites', () {
    DioException err(int code, Object data) => DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: code, data: data),
          type: DioExceptionType.badResponse,
        );
    expect(
      ApiException.from(err(400, {
        'errors': [
          {'defaultUserMessage': 'Insufficient account balance.'}
        ]
      })).message,
      'Insufficient account balance.',
    );
    expect(ApiException.from(err(401, {'error': 'invalid_grant', 'error_description': 'Invalid user credentials'})).message,
        contains('OTP'));
    expect(ApiException.from(err(400, {'error': 'invalid_grant', 'error_description': 'Account is not fully set up'})).message,
        contains('finalisé'));
  });
}
