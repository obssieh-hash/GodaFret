import '../core/formatters.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'auth/auth_service.dart';
import 'bank_repository.dart';

/// Implémentation sur l'API REST d'Apache Fineract (`/fineract-provider/api/v1`).
///
/// Le client Fineract de l'utilisateur connecté est retrouvé :
/// 1. via le claim `fineract_client_id` du jeton Keycloak ;
/// 2. sinon via `GET /clients?externalId=<identifiant>` (l'identifiant de
///    connexion est enregistré comme « External Id » du client dans Mifos X).
class FineractRepository implements BankRepository {
  FineractRepository(this.api, this.auth);

  final FineractApi api;
  final AuthService auth;
  Client? _client;

  static const _savingsType = 2;

  Map<String, dynamic> get _fmt => {'locale': 'en', 'dateFormat': 'yyyy-MM-dd'};

  int get _clientId {
    final c = _client;
    if (c == null) throw ApiException('Profil client non chargé.');
    return c.id;
  }

  @override
  Future<Client> loadClient() async {
    var id = auth.clientIdHint;
    if (id == null) {
      final username = auth.username;
      if (username == null) throw ApiException('Utilisateur inconnu.');
      final page = await api.get('/clients', query: {'externalId': username, 'limit': 1}) as Map;
      final items = (page['pageItems'] as List?) ?? const [];
      if (items.isEmpty) {
        throw ApiException(
          "Aucun client n'est rattaché à l'identifiant « $username ». "
          "Renseignez-le comme External Id du client dans Mifos X.",
        );
      }
      id = (items.first as Map)['id'] as int;
    }
    final data = await api.get('/clients/$id') as Map<String, dynamic>;
    return _client = Client.fromJson(data);
  }

  @override
  Future<ClientAccounts> accounts() async {
    final data = await api.get('/clients/$_clientId/accounts') as Map;
    final savings = ((data['savingsAccounts'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(SavingsAccount.fromSummary)
        .where((a) => a.active)
        .toList();
    final loans = ((data['loanAccounts'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LoanAccount.fromSummary)
        .where((l) => l.state != LoanState.other)
        .toList();
    return ClientAccounts(savings, loans);
  }

  @override
  Future<SavingsDetail> savingsDetail(int accountId) async {
    final data = await api.get('/savingsaccounts/$accountId', query: {'associations': 'transactions'})
        as Map<String, dynamic>;
    final account = SavingsAccount.fromDetail(data);
    final txs = ((data['transactions'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((t) => t['reversed'] != true)
        .map((t) => BankTransaction.fromSavingsJson(
              t,
              accountId: accountId,
              currency: account.currency,
              accountLabel: account.productName,
            ))
        .toList();
    return SavingsDetail(account, txs);
  }

  @override
  Future<LoanAccount> loanDetail(int loanId) async {
    final data = await api.get('/loans/$loanId', query: {'associations': 'repaymentSchedule,transactions'})
        as Map<String, dynamic>;
    return LoanAccount.fromDetail(data);
  }

  @override
  Future<List<PaymentType>> paymentTypes() async {
    try {
      final data = await api.get('/paymenttypes') as List;
      return data.cast<Map>().map((p) => PaymentType(p['id'] as int, '${p['name']}')).toList();
    } on ApiException {
      return const [];
    }
  }

  @override
  Future<void> deposit(int accountId, double amount, {int? paymentTypeId, String? note}) =>
      _savingsTx(accountId, 'deposit', amount, paymentTypeId, note);

  @override
  Future<void> withdraw(int accountId, double amount, {int? paymentTypeId, String? note}) =>
      _savingsTx(accountId, 'withdrawal', amount, paymentTypeId, note);

  Future<void> _savingsTx(int accountId, String command, double amount, int? paymentTypeId, String? note) async {
    await api.post(
      '/savingsaccounts/$accountId/transactions',
      query: {'command': command},
      body: {
        ..._fmt,
        'transactionDate': Fmt.api(DateTime.now()),
        'transactionAmount': amount,
        'paymentTypeId': ?paymentTypeId,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  @override
  Future<Beneficiary> findBeneficiary(String accountNo) async {
    final results = await api.get('/search', query: {
      'query': accountNo.trim(),
      'resource': 'savings',
      'exactMatch': true,
    }) as List;
    final match = results.cast<Map>().where((r) => '${r['entityAccountNo']}' == accountNo.trim()).toList();
    if (match.isEmpty) throw ApiException('Aucun compte ne correspond à ce numéro.');
    final r = match.first;
    final accountId = r['entityId'] as int;
    final account = await api.get('/savingsaccounts/$accountId') as Map;
    final clientId = (account['clientId'] ?? r['parentId']) as int;
    final client = await api.get('/clients/$clientId') as Map;
    return Beneficiary(
      accountId: accountId,
      accountNo: '${r['entityAccountNo']}',
      clientId: clientId,
      clientName: '${account['clientName'] ?? r['parentName'] ?? client['displayName']}',
      officeId: client['officeId'] as int,
    );
  }

  @override
  Future<void> transfer({
    required SavingsAccount from,
    required Beneficiary to,
    required double amount,
    required String description,
  }) async {
    final client = _client!;
    await api.post('/accounttransfers', body: {
      ..._fmt,
      'fromOfficeId': client.officeId,
      'fromClientId': client.id,
      'fromAccountType': _savingsType,
      'fromAccountId': from.id,
      'toOfficeId': to.officeId,
      'toClientId': to.clientId,
      'toAccountType': _savingsType,
      'toAccountId': to.accountId,
      'transferAmount': amount,
      'transferDate': Fmt.api(DateTime.now()),
      'transferDescription': description.isEmpty ? 'Transfert mobile' : description,
    });
  }

  @override
  Future<List<LoanProduct>> loanProducts() async {
    final tpl = await api.get('/loans/template', query: {
      'templateType': 'individual',
      'clientId': _clientId,
    }) as Map;
    final options = (tpl['productOptions'] as List?) ?? const [];
    final products = <LoanProduct>[];
    for (final o in options.cast<Map>()) {
      try {
        final p = await api.get('/loanproducts/${o['id']}') as Map<String, dynamic>;
        products.add(LoanProduct.fromJson(p));
      } on ApiException {
        products.add(LoanProduct(id: o['id'] as int, name: '${o['name']}'));
      }
    }
    return products;
  }

  /// Construit le corps d'une demande de prêt à partir du modèle du produit.
  Future<Map<String, dynamic>> _loanBody(LoanProduct product, double amount, int repayments) async {
    final t = await api.get('/loans/template', query: {
      'templateType': 'individual',
      'clientId': _clientId,
      'productId': product.id,
    }) as Map;
    int? idOf(String key) => (t[key] as Map?)?['id'] as int?;
    final every = (t['repaymentEvery'] as int?) ?? 1;
    final today = Fmt.api(DateTime.now());
    return {
      ..._fmt,
      'loanType': 'individual',
      'clientId': _clientId,
      'productId': product.id,
      'principal': amount,
      'numberOfRepayments': repayments,
      'repaymentEvery': every,
      'repaymentFrequencyType': idOf('repaymentFrequencyType'),
      'loanTermFrequency': repayments * every,
      'loanTermFrequencyType': idOf('repaymentFrequencyType'),
      'interestRatePerPeriod': t['interestRatePerPeriod'],
      'amortizationType': idOf('amortizationType'),
      'interestType': idOf('interestType'),
      'interestCalculationPeriodType': idOf('interestCalculationPeriodType'),
      'transactionProcessingStrategyCode': t['transactionProcessingStrategyCode'],
      'expectedDisbursementDate': today,
      'submittedOnDate': today,
    }..removeWhere((k, v) => v == null);
  }

  @override
  Future<LoanSimulation> simulateLoan(LoanProduct product, double amount, int repayments) async {
    final body = await _loanBody(product, amount, repayments);
    final data = await api.post('/loans', query: {'command': 'calculateLoanSchedule'}, body: body) as Map;
    final periods = ((data['periods'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((p) => p['period'] != null)
        .map(Installment.fromJson)
        .toList();
    return LoanSimulation(
      installments: periods,
      totalInterest: toDouble(data['totalInterestCharged']),
      totalRepayment: toDouble(data['totalRepaymentExpected']),
    );
  }

  @override
  Future<void> applyForLoan(LoanProduct product, double amount, int repayments, {String? purpose}) async {
    final body = await _loanBody(product, amount, repayments);
    final res = await api.post('/loans', body: body) as Map;
    final loanId = res['loanId'] ?? res['resourceId'];
    if (purpose != null && purpose.isNotEmpty && loanId != null) {
      try {
        await api.post('/loans/$loanId/notes', body: {'note': 'Objet du prêt : $purpose'});
      } on ApiException {
        // La note est facultative : la demande est déjà enregistrée.
      }
    }
  }

  @override
  Future<void> repayLoan(int loanId, double amount, {int? paymentTypeId}) async {
    await api.post(
      '/loans/$loanId/transactions',
      query: {'command': 'repayment'},
      body: {
        ..._fmt,
        'transactionDate': Fmt.api(DateTime.now()),
        'transactionAmount': amount,
        'paymentTypeId': ?paymentTypeId,
        'note': 'Remboursement via application mobile',
      },
    );
  }

  @override
  Future<List<AppNotification>> notifications() async {
    final data = await api.get('/notifications', query: {'limit': 50, 'orderBy': 'id', 'sortOrder': 'DESC'});
    final items = data is Map ? (data['pageItems'] as List?) ?? const [] : data as List;
    return items.cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList();
  }

  @override
  Future<void> markNotificationsRead() => api.put('/notifications');
}
