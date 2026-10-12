import 'dart:math';

import '../models/models.dart';
import 'api_client.dart';
import 'bank_repository.dart';

/// Banque fictive en mémoire pour essayer l'application sans serveur.
class DemoRepository implements BankRepository {
  DemoRepository() {
    _seed();
  }

  static const _cur = 'DJF';
  final _rng = Random(7);
  int _nextId = 1000;

  late final Client _client;
  final Map<int, SavingsAccount> _savings = {};
  final Map<int, List<BankTransaction>> _savingsTx = {};
  final Map<int, LoanAccount> _loans = {};
  final List<AppNotification> _notifications = [];

  /// Contacts, marchand et agent connus du mode démo (par téléphone et par compte).
  static const _recipients = [
    Beneficiary(accountId: 201, accountNo: '000000201', clientId: 2, clientName: 'Ahmed Hassan Moussa', officeId: 1, phone: '77202020'),
    Beneficiary(accountId: 301, accountNo: '000000301', clientId: 3, clientName: 'Hodan Abdi Farah', officeId: 1, phone: '77303030'),
    Beneficiary(accountId: 401, accountNo: '000000401', clientId: 4, clientName: 'Boulangerie La Palmeraie', officeId: 1, phone: '21350001'),
    Beneficiary(accountId: 501, accountNo: '000000501', clientId: 5, clientName: 'Agent GB Balbala', officeId: 1, phone: '77990001'),
  ];

  static const _products = [
    LoanProduct(
      id: 1,
      name: 'Prêt personnel',
      description: 'Pour vos projets et imprévus.',
      minPrincipal: 50000,
      maxPrincipal: 2000000,
      defaultPrincipal: 300000,
      minRepayments: 6,
      maxRepayments: 48,
      defaultRepayments: 12,
      interestRate: 1.0,
      currency: _cur,
    ),
    LoanProduct(
      id: 2,
      name: 'Microcrédit commerce',
      description: 'Stock et fonds de roulement pour votre activité.',
      minPrincipal: 20000,
      maxPrincipal: 500000,
      defaultPrincipal: 100000,
      minRepayments: 3,
      maxRepayments: 18,
      defaultRepayments: 6,
      interestRate: 1.5,
      currency: _cur,
    ),
    LoanProduct(
      id: 3,
      name: 'Prêt équipement',
      description: 'Moto, frigo, panneaux solaires…',
      minPrincipal: 200000,
      maxPrincipal: 5000000,
      defaultPrincipal: 1000000,
      minRepayments: 12,
      maxRepayments: 60,
      defaultRepayments: 24,
      interestRate: 0.9,
      currency: _cur,
    ),
  ];

  Future<void> _latency([int ms = 350]) => Future<void>.delayed(Duration(milliseconds: ms));

  void _seed() {
    final now = DateTime.now();
    _client = Client(
      id: 1,
      accountNo: '000000001',
      displayName: 'Fatouma Ali Houssein',
      firstname: 'Fatouma',
      lastname: 'Ali Houssein',
      mobileNo: '77101010',
      email: 'fatouma.ali@example.dj',
      officeId: 1,
      officeName: 'Agence Djibouti Centre',
      activationDate: DateTime(now.year - 2, 3, 12),
      externalId: '77101010',
    );

    _savings[101] = const SavingsAccount(
      id: 101,
      accountNo: '000000101',
      productName: 'Portefeuille GB Pay',
      balance: 0,
      currency: _cur,
    );
    _savings[102] = const SavingsAccount(
      id: 102,
      accountNo: '000000102',
      productName: 'Épargne',
      balance: 0,
      currency: _cur,
    );
    _savingsTx[101] = [];
    _savingsTx[102] = [];

    final seed = <(int, TxKind, String, double, DateTime)>[];
    void s(int a, TxKind k, String l, double v, DateTime d) => seed.add((a, k, l, v, d));

    // Six mois d'historique.
    for (var m = 5; m >= 0; m--) {
      final month = DateTime(now.year, now.month - m, 1);
      s(101, TxKind.transferIn, 'Salaire', 180000 + _rng.nextInt(5) * 1000.0, month.add(const Duration(days: 1)));
      s(101, TxKind.transferOut, 'Retrait chez Agent GB Balbala', -(10000 + _rng.nextInt(4) * 5000.0), month.add(const Duration(days: 3)));
      s(101, TxKind.transferOut, 'Loyer · Hodan Abdi Farah', -60000, month.add(const Duration(days: 5)));
      s(101, TxKind.transferOut, 'Paiement Boulangerie La Palmeraie', -(2000 + _rng.nextInt(6) * 500.0), month.add(const Duration(days: 8)));
      s(101, TxKind.transferOut, 'Vers Épargne', -15000, month.add(const Duration(days: 10)));
      s(102, TxKind.transferIn, 'Depuis Portefeuille GB Pay', 15000, month.add(const Duration(days: 10)));
      s(101, TxKind.transferOut, 'Échéance Prêt personnel', -23536, month.add(const Duration(days: 15)));
      if (m.isEven) {
        s(101, TxKind.transferIn, 'Reçu de Ahmed Hassan Moussa', 5000, month.add(const Duration(days: 18)));
      }
      s(101, TxKind.transferOut, 'Envoi à Ahmed Hassan Moussa', -(3000 + _rng.nextInt(4) * 1000.0), month.add(const Duration(days: 21)));
    }
    s(101, TxKind.deposit, 'Dépôt en agence', 50000, DateTime(now.year, now.month - 6, 2));
    s(102, TxKind.deposit, 'Dépôt en agence', 120000, DateTime(now.year, now.month - 6, 2));

    seed.sort((x, y) => x.$5.compareTo(y.$5));
    for (final t in seed.where((t) => !t.$5.isAfter(now))) {
      _add(t.$1, t.$2, t.$3, t.$4, t.$5);
    }

    _loans[501] = _buildLoan(
      id: 501,
      product: 'Prêt personnel',
      principal: 500000,
      repayments: 24,
      monthlyRate: 0.01,
      start: DateTime(now.year, now.month - 6, 15),
      paidPeriods: now.day >= 15 ? 6 : 5,
    );

    _notifications.addAll([
      AppNotification(
        id: 3,
        title: 'Échéance à venir',
        body: 'Votre échéance de 23\u00a0536\u00a0Fdj sera prélevée le 15.',
        createdAt: now.subtract(const Duration(hours: 3)),
        read: false,
      ),
      AppNotification(
        id: 2,
        title: 'Argent reçu',
        body: 'Vous avez reçu 180\u00a0000\u00a0Fdj (salaire) sur votre portefeuille.',
        createdAt: now.subtract(const Duration(days: 2)),
        read: false,
      ),
      AppNotification(
        id: 1,
        title: 'Sécurité',
        body: 'Nouvelle connexion depuis un appareil mobile avec authentification forte.',
        createdAt: now.subtract(const Duration(days: 6)),
        read: true,
      ),
    ]);
  }

  void _add(int accountId, TxKind kind, String label, double amount, DateTime date) {
    final list = _savingsTx[accountId]!;
    final acc = _savings[accountId]!;
    final balance = acc.balance + amount;
    list.add(BankTransaction(
      id: _nextId++,
      accountId: accountId,
      kind: kind,
      label: label,
      amount: amount,
      date: date.isAfter(DateTime.now()) ? DateTime.now() : date,
      currency: _cur,
      runningBalance: balance,
      accountLabel: acc.productName,
    ));
    _savings[accountId] = SavingsAccount(
      id: acc.id,
      accountNo: acc.accountNo,
      productName: acc.productName,
      balance: balance,
      currency: acc.currency,
    );
  }

  static List<Installment> amortize(double principal, int n, double monthlyRate, DateTime start, {int paid = 0}) {
    final r = monthlyRate;
    final payment = r == 0 ? principal / n : principal * r / (1 - pow(1 + r, -n));
    var remaining = principal;
    final out = <Installment>[];
    for (var i = 1; i <= n; i++) {
      // Montants entiers : le franc Djibouti n'a pas de centimes.
      final interest = (remaining * r).roundToDouble();
      final princ = i == n ? remaining : (payment - interest).roundToDouble();
      remaining -= princ;
      final total = princ + interest;
      final done = i <= paid;
      out.add(Installment(
        number: i,
        dueDate: DateTime(start.year, start.month + i, start.day),
        principal: princ,
        interest: interest,
        fees: 0,
        totalDue: total,
        paid: done ? total : 0,
        outstanding: done ? 0 : total,
        complete: done,
      ));
    }
    return out;
  }

  LoanAccount _buildLoan({
    required int id,
    required String product,
    required double principal,
    required int repayments,
    required double monthlyRate,
    required DateTime start,
    required int paidPeriods,
    LoanState state = LoanState.active,
  }) {
    final schedule = amortize(principal, repayments, monthlyRate, start, paid: paidPeriods);
    final txs = <BankTransaction>[
      BankTransaction(
        id: _nextId++,
        accountId: id,
        kind: TxKind.disbursement,
        label: 'Décaissement',
        amount: principal,
        date: start,
        currency: _cur,
        accountLabel: product,
        isLoan: true,
      ),
      for (final i in schedule.where((i) => i.complete))
        BankTransaction(
          id: _nextId++,
          accountId: id,
          kind: TxKind.repayment,
          label: 'Remboursement échéance ${i.number}',
          amount: -i.totalDue,
          date: i.dueDate,
          currency: _cur,
          accountLabel: product,
          isLoan: true,
        ),
    ];
    return _loanFrom(id, product, principal, repayments, monthlyRate, schedule, txs, state);
  }

  LoanAccount _loanFrom(
    int id,
    String product,
    double principal,
    int repayments,
    double monthlyRate,
    List<Installment> schedule,
    List<BankTransaction> txs,
    LoanState state,
  ) {
    final outstanding = schedule.fold<double>(0, (s, i) => s + i.outstanding);
    final paid = schedule.fold<double>(0, (s, i) => s + i.paid);
    final overdue = schedule.where((i) => i.overdue).fold<double>(0, (s, i) => s + i.outstanding);
    return LoanAccount(
      id: id,
      accountNo: '000000$id',
      productName: product,
      principal: principal,
      outstanding: state == LoanState.pending ? 0 : outstanding,
      amountPaid: paid,
      overdue: overdue,
      currency: _cur,
      state: outstanding <= 0.005 && state == LoanState.active ? LoanState.closed : state,
      statusLabel: switch (state) {
        LoanState.pending => "En attente d'approbation",
        LoanState.active => 'Actif',
        LoanState.closed => 'Soldé',
        _ => '',
      },
      interestRate: monthlyRate * 100,
      numberOfRepayments: repayments,
      schedule: schedule,
      transactions: txs,
    );
  }

  @override
  Future<Client> loadClient() async {
    await _latency();
    return _client;
  }

  @override
  Future<ClientAccounts> accounts() async {
    await _latency();
    return ClientAccounts(_savings.values.toList(), _loans.values.toList());
  }

  @override
  Future<SavingsDetail> savingsDetail(int accountId) async {
    await _latency(250);
    final acc = _savings[accountId];
    if (acc == null) throw ApiException('Compte introuvable.');
    final txs = [..._savingsTx[accountId]!]..sort((a, b) => b.date.compareTo(a.date));
    return SavingsDetail(acc, txs);
  }

  @override
  Future<LoanAccount> loanDetail(int loanId) async {
    await _latency(250);
    final loan = _loans[loanId];
    if (loan == null) throw ApiException('Prêt introuvable.');
    return loan;
  }

  @override
  Future<Beneficiary> findRecipient(String query) async {
    await _latency(500);
    final q = query.trim();
    final digits = normalizePhone(q);
    for (final a in _savings.values) {
      if (a.accountNo == q) {
        return Beneficiary(
          accountId: a.id,
          accountNo: a.accountNo,
          clientId: _client.id,
          clientName: '${_client.displayName} · ${a.productName}',
          officeId: 1,
          phone: _client.mobileNo,
        );
      }
    }
    for (final r in _recipients) {
      if (r.accountNo == q || (digits.isNotEmpty && r.phone == digits)) return r;
    }
    throw ApiException('Aucun compte Golden Bridge ne correspond à « $q ».');
  }

  @override
  Future<void> transfer({
    required SavingsAccount from,
    required Beneficiary to,
    required double amount,
    required String description,
  }) async {
    await _latency(900);
    _check(amount);
    if (_savings[from.id]!.balance < amount) throw ApiException('Solde insuffisant pour ce transfert.');
    if (to.accountId == from.id) throw ApiException('Choisissez un compte différent.');
    final label = description.isEmpty ? 'Envoi à ${to.clientName}' : description;
    _add(from.id, TxKind.transferOut, label, -amount, DateTime.now());
    if (_savings.containsKey(to.accountId)) {
      _add(to.accountId, TxKind.transferIn, 'Depuis ${from.productName}', amount, DateTime.now());
    }
    _notify('Opération réussie', '$label : ${amount.round()} Fdj.');
  }

  @override
  Future<List<LoanProduct>> loanProducts() async {
    await _latency();
    return _products;
  }

  @override
  Future<LoanSimulation> simulateLoan(LoanProduct product, double amount, int repayments) async {
    await _latency(250);
    final schedule = amortize(amount, repayments, (product.interestRate ?? 0) / 100, DateTime.now());
    final interest = schedule.fold<double>(0, (s, i) => s + i.interest);
    return LoanSimulation(installments: schedule, totalInterest: interest, totalRepayment: amount + interest);
  }

  @override
  Future<void> applyForLoan(LoanProduct product, double amount, int repayments, {String? purpose}) async {
    await _latency(900);
    final id = 600 + _loans.length;
    final schedule = amortize(amount, repayments, (product.interestRate ?? 0) / 100, DateTime.now());
    _loans[id] = _loanFrom(
      id,
      product.name,
      amount,
      repayments,
      (product.interestRate ?? 0) / 100,
      schedule,
      const [],
      LoanState.pending,
    );
    _notify('Demande de prêt reçue', 'Votre demande de ${product.name} est en cours d\'étude.');
  }

  @override
  Future<void> repayLoan(int loanId, double amount, {required SavingsAccount from}) async {
    await _latency(800);
    _check(amount);
    final loan = _loans[loanId]!;
    if (amount > loan.outstanding + 0.005) throw ApiException('Le montant dépasse le capital restant dû.');
    final current = _savings[from.id]!;
    if (current.balance < amount) throw ApiException('Solde insuffisant sur ${current.productName}.');
    var left = amount;
    final schedule = [
      for (final i in loan.schedule)
        if (i.complete || left <= 0)
          i
        else
          () {
            final pay = min(left, i.outstanding);
            left -= pay;
            final rest = i.outstanding - pay;
            return Installment(
              number: i.number,
              dueDate: i.dueDate,
              principal: i.principal,
              interest: i.interest,
              fees: i.fees,
              totalDue: i.totalDue,
              paid: i.paid + pay,
              outstanding: rest,
              complete: rest <= 0.005,
            );
          }(),
    ];
    final tx = BankTransaction(
      id: _nextId++,
      accountId: loanId,
      kind: TxKind.repayment,
      label: 'Remboursement',
      amount: -amount,
      date: DateTime.now(),
      currency: _cur,
      accountLabel: loan.productName,
      isLoan: true,
    );
    _loans[loanId] = _loanFrom(
      loan.id,
      loan.productName,
      loan.principal,
      loan.numberOfRepayments ?? schedule.length,
      (loan.interestRate ?? 0) / 100,
      schedule,
      [...loan.transactions, tx],
      LoanState.active,
    );
    _add(from.id, TxKind.transferOut, 'Remboursement ${loan.productName}', -amount, DateTime.now());
    _notify('Remboursement reçu', 'Merci ! Votre paiement a été imputé sur votre prêt.');
  }

  @override
  Future<List<AppNotification>> notifications() async {
    await _latency(200);
    return List.of(_notifications);
  }

  @override
  Future<void> markNotificationsRead() async {
    for (var i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      _notifications[i] = AppNotification(id: n.id, title: n.title, body: n.body, createdAt: n.createdAt, read: true);
    }
  }

  void _check(double amount) {
    if (amount <= 0) throw ApiException('Saisissez un montant positif.');
  }

  void _notify(String title, String body) {
    _notifications.insert(
      0,
      AppNotification(id: _nextId++, title: title, body: body, createdAt: DateTime.now(), read: false),
    );
  }
}
