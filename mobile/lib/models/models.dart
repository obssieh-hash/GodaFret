import '../core/formatters.dart';

/// Client Fineract (`GET /clients/{id}`).
class Client {
  const Client({
    required this.id,
    required this.accountNo,
    required this.displayName,
    this.firstname,
    this.lastname,
    this.mobileNo,
    this.email,
    this.officeId,
    this.officeName,
    this.activationDate,
    this.externalId,
    this.status = 'Actif',
  });

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        id: j['id'] as int,
        accountNo: '${j['accountNo'] ?? ''}',
        displayName: '${j['displayName'] ?? ''}',
        firstname: j['firstname'] as String?,
        lastname: j['lastname'] as String?,
        mobileNo: j['mobileNo'] as String?,
        email: j['emailAddress'] as String?,
        officeId: j['officeId'] as int?,
        officeName: j['officeName'] as String?,
        activationDate: Fmt.parseFineract(j['activationDate']),
        externalId: j['externalId'] as String?,
        status: (j['status'] as Map?)?['value'] as String? ?? 'Actif',
      );

  final int id;
  final String accountNo;
  final String displayName;
  final String? firstname;
  final String? lastname;
  final String? mobileNo;
  final String? email;
  final int? officeId;
  final String? officeName;
  final DateTime? activationDate;
  final String? externalId;
  final String status;

  String get firstName => firstname ?? displayName.split(' ').first;
}

class SavingsAccount {
  const SavingsAccount({
    required this.id,
    required this.accountNo,
    required this.productName,
    required this.balance,
    required this.currency,
    this.availableBalance,
    this.active = true,
    this.status = 'Actif',
    this.clientId,
    this.clientName,
  });

  factory SavingsAccount.fromSummary(Map<String, dynamic> j) => SavingsAccount(
        id: j['id'] as int,
        accountNo: '${j['accountNo'] ?? ''}',
        productName: '${j['productName'] ?? 'Compte'}',
        balance: toDouble(j['accountBalance']),
        currency: (j['currency'] as Map?)?['code'] as String? ?? 'EUR',
        active: (j['status'] as Map?)?['active'] as bool? ?? true,
        status: (j['status'] as Map?)?['value'] as String? ?? '',
      );

  factory SavingsAccount.fromDetail(Map<String, dynamic> j) {
    final summary = (j['summary'] as Map?) ?? const {};
    return SavingsAccount(
      id: j['id'] as int,
      accountNo: '${j['accountNo'] ?? ''}',
      productName: '${j['savingsProductName'] ?? 'Compte'}',
      balance: toDouble(summary['accountBalance']),
      availableBalance: summary['availableBalance'] == null ? null : toDouble(summary['availableBalance']),
      currency: (j['currency'] as Map?)?['code'] as String? ?? 'EUR',
      active: (j['status'] as Map?)?['active'] as bool? ?? true,
      status: (j['status'] as Map?)?['value'] as String? ?? '',
      clientId: j['clientId'] as int?,
      clientName: j['clientName'] as String?,
    );
  }

  final int id;
  final String accountNo;
  final String productName;
  final double balance;
  final double? availableBalance;
  final String currency;
  final bool active;
  final String status;
  final int? clientId;
  final String? clientName;

  double get available => availableBalance ?? balance;
}

enum LoanState { pending, approved, active, closed, rejected, other }

class LoanAccount {
  const LoanAccount({
    required this.id,
    required this.accountNo,
    required this.productName,
    required this.principal,
    required this.outstanding,
    required this.currency,
    required this.state,
    required this.statusLabel,
    this.amountPaid = 0,
    this.overdue = 0,
    this.interestRate,
    this.numberOfRepayments,
    this.schedule = const [],
    this.transactions = const [],
  });

  factory LoanAccount.fromSummary(Map<String, dynamic> j) => LoanAccount(
        id: j['id'] as int,
        accountNo: '${j['accountNo'] ?? ''}',
        productName: '${j['productName'] ?? 'Prêt'}',
        principal: toDouble(j['originalLoan'] ?? j['principal']),
        outstanding: toDouble(j['loanBalance']),
        amountPaid: toDouble(j['amountPaid']),
        currency: (j['currency'] as Map?)?['code'] as String? ?? 'EUR',
        state: _state(j['status'] as Map?),
        statusLabel: (j['status'] as Map?)?['value'] as String? ?? '',
      );

  factory LoanAccount.fromDetail(Map<String, dynamic> j) {
    final summary = (j['summary'] as Map?) ?? const {};
    final currency = (j['currency'] as Map?)?['code'] as String? ?? 'EUR';
    final periods = ((j['repaymentSchedule'] as Map?)?['periods'] as List?) ?? const [];
    final txs = (j['transactions'] as List?) ?? const [];
    return LoanAccount(
      id: j['id'] as int,
      accountNo: '${j['accountNo'] ?? ''}',
      productName: '${j['loanProductName'] ?? 'Prêt'}',
      principal: toDouble(j['principal']),
      outstanding: toDouble(summary['totalOutstanding']),
      amountPaid: toDouble(summary['totalRepayment']),
      overdue: toDouble(summary['totalOverdue']),
      currency: currency,
      state: _state(j['status'] as Map?),
      statusLabel: (j['status'] as Map?)?['value'] as String? ?? '',
      interestRate: j['interestRatePerPeriod'] == null ? null : toDouble(j['interestRatePerPeriod']),
      numberOfRepayments: j['numberOfRepayments'] as int?,
      schedule: periods
          .cast<Map<String, dynamic>>()
          .where((p) => p['period'] != null)
          .map(Installment.fromJson)
          .toList(),
      transactions: txs
          .cast<Map<String, dynamic>>()
          .where((t) => t['manuallyReversed'] != true)
          .map((t) => BankTransaction.fromLoanJson(t, accountId: j['id'] as int, currency: currency))
          .toList(),
    );
  }

  static LoanState _state(Map? status) {
    if (status == null) return LoanState.other;
    if (status['pendingApproval'] == true) return LoanState.pending;
    if (status['waitingForDisbursal'] == true) return LoanState.approved;
    if (status['active'] == true) return LoanState.active;
    if (status['closed'] == true || status['closedObligationsMet'] == true) return LoanState.closed;
    final code = '${status['code'] ?? ''}';
    if (code.contains('rejected') || code.contains('withdrawn')) return LoanState.rejected;
    return LoanState.other;
  }

  final int id;
  final String accountNo;
  final String productName;
  final double principal;
  final double outstanding;
  final double amountPaid;
  final double overdue;
  final String currency;
  final LoanState state;
  final String statusLabel;
  final double? interestRate;
  final int? numberOfRepayments;
  final List<Installment> schedule;
  final List<BankTransaction> transactions;

  double get progress => principal <= 0 ? 0 : (1 - outstanding / (principal + _interestTotal)).clamp(0, 1);

  double get _interestTotal => schedule.fold(0, (s, i) => s + i.interest);

  Installment? get nextInstallment {
    for (final i in schedule) {
      if (!i.complete) return i;
    }
    return null;
  }
}

class Installment {
  const Installment({
    required this.number,
    required this.dueDate,
    required this.principal,
    required this.interest,
    required this.fees,
    required this.totalDue,
    required this.paid,
    required this.outstanding,
    required this.complete,
  });

  factory Installment.fromJson(Map<String, dynamic> j) => Installment(
        number: j['period'] as int,
        dueDate: Fmt.parseFineract(j['dueDate']) ?? DateTime.now(),
        principal: toDouble(j['principalDue'] ?? j['principalOriginalDue']),
        interest: toDouble(j['interestDue'] ?? j['interestOriginalDue']),
        fees: toDouble(j['feeChargesDue']) + toDouble(j['penaltyChargesDue']),
        totalDue: toDouble(j['totalDueForPeriod']),
        paid: toDouble(j['totalPaidForPeriod']),
        outstanding: toDouble(j['totalOutstandingForPeriod'] ?? j['totalDueForPeriod']),
        complete: j['complete'] as bool? ?? false,
      );

  final int number;
  final DateTime dueDate;
  final double principal;
  final double interest;
  final double fees;
  final double totalDue;
  final double paid;
  final double outstanding;
  final bool complete;

  bool get overdue => !complete && dueDate.isBefore(DateTime.now());
}

enum TxKind { deposit, withdrawal, transferIn, transferOut, disbursement, repayment, fee, interest, other }

class BankTransaction {
  const BankTransaction({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.label,
    required this.amount,
    required this.date,
    required this.currency,
    this.runningBalance,
    this.accountLabel,
    this.isLoan = false,
  });

  factory BankTransaction.fromSavingsJson(
    Map<String, dynamic> j, {
    required int accountId,
    required String currency,
    String? accountLabel,
  }) {
    final type = (j['transactionType'] as Map?) ?? const {};
    final transfer = j['transfer'] != null;
    final TxKind kind;
    if (type['deposit'] == true) {
      kind = transfer ? TxKind.transferIn : TxKind.deposit;
    } else if (type['withdrawal'] == true) {
      kind = transfer ? TxKind.transferOut : TxKind.withdrawal;
    } else if (type['interestPosting'] == true) {
      kind = TxKind.interest;
    } else if (type['feeDeduction'] == true || type['annualFee'] == true || type['withdrawalFee'] == true) {
      kind = TxKind.fee;
    } else {
      kind = TxKind.other;
    }
    final raw = toDouble(j['amount']);
    final credit = kind == TxKind.deposit || kind == TxKind.transferIn || kind == TxKind.interest;
    return BankTransaction(
      id: j['id'] as int,
      accountId: accountId,
      kind: kind,
      label: '${type['value'] ?? 'Opération'}',
      amount: credit ? raw : -raw,
      date: Fmt.parseFineract(j['date']) ?? DateTime.now(),
      currency: currency,
      runningBalance: j['runningBalance'] == null ? null : toDouble(j['runningBalance']),
      accountLabel: accountLabel,
    );
  }

  factory BankTransaction.fromLoanJson(
    Map<String, dynamic> j, {
    required int accountId,
    required String currency,
    String? accountLabel,
  }) {
    final type = (j['type'] as Map?) ?? const {};
    final kind = type['disbursement'] == true
        ? TxKind.disbursement
        : type['repayment'] == true
            ? TxKind.repayment
            : TxKind.other;
    final raw = toDouble(j['amount']);
    return BankTransaction(
      id: j['id'] as int,
      accountId: accountId,
      kind: kind,
      label: '${type['value'] ?? 'Opération de prêt'}',
      amount: kind == TxKind.disbursement ? raw : -raw,
      date: Fmt.parseFineract(j['date']) ?? DateTime.now(),
      currency: currency,
      runningBalance: j['outstandingLoanBalance'] == null ? null : toDouble(j['outstandingLoanBalance']),
      accountLabel: accountLabel,
      isLoan: true,
    );
  }

  final int id;
  final int accountId;
  final TxKind kind;
  final String label;

  /// Montant signé : positif = crédit, négatif = débit.
  final double amount;
  final DateTime date;
  final String currency;
  final double? runningBalance;
  final String? accountLabel;
  final bool isLoan;

  bool get isCredit => amount >= 0;

  BankTransaction withAccountLabel(String label) => BankTransaction(
        id: id,
        accountId: accountId,
        kind: kind,
        label: this.label,
        amount: amount,
        date: date,
        currency: currency,
        runningBalance: runningBalance,
        accountLabel: label,
        isLoan: isLoan,
      );
}

class LoanProduct {
  const LoanProduct({
    required this.id,
    required this.name,
    this.minPrincipal,
    this.maxPrincipal,
    this.defaultPrincipal,
    this.minRepayments,
    this.maxRepayments,
    this.defaultRepayments,
    this.interestRate,
    this.currency = 'EUR',
    this.description,
  });

  factory LoanProduct.fromJson(Map<String, dynamic> j) => LoanProduct(
        id: j['id'] as int,
        name: '${j['name'] ?? 'Prêt'}',
        description: j['description'] as String?,
        minPrincipal: j['minPrincipal'] == null ? null : toDouble(j['minPrincipal']),
        maxPrincipal: j['maxPrincipal'] == null ? null : toDouble(j['maxPrincipal']),
        defaultPrincipal: j['principal'] == null ? null : toDouble(j['principal']),
        minRepayments: j['minNumberOfRepayments'] as int?,
        maxRepayments: j['maxNumberOfRepayments'] as int?,
        defaultRepayments: j['numberOfRepayments'] as int?,
        interestRate: j['interestRatePerPeriod'] == null ? null : toDouble(j['interestRatePerPeriod']),
        currency: (j['currency'] as Map?)?['code'] as String? ?? 'EUR',
      );

  final int id;
  final String name;
  final String? description;
  final double? minPrincipal;
  final double? maxPrincipal;
  final double? defaultPrincipal;
  final int? minRepayments;
  final int? maxRepayments;
  final int? defaultRepayments;
  final double? interestRate;
  final String currency;
}

/// Bénéficiaire d'un transfert interne : un compte épargne de la banque.
class Beneficiary {
  const Beneficiary({
    required this.accountId,
    required this.accountNo,
    required this.clientId,
    required this.clientName,
    required this.officeId,
  });

  final int accountId;
  final String accountNo;
  final int clientId;
  final String clientName;
  final int officeId;
}

class PaymentType {
  const PaymentType(this.id, this.name);
  final int id;
  final String name;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.objectType,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final type = '${j['objectType'] ?? ''}';
    final action = '${j['action'] ?? ''}';
    return AppNotification(
      id: j['id'] as int,
      title: _title(type, action),
      body: '${j['content'] ?? ''}',
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now(),
      read: j['isRead'] as bool? ?? false,
      objectType: type,
    );
  }

  static String _title(String type, String action) {
    final t = type.toLowerCase();
    if (t.contains('loan')) return 'Prêt';
    if (t.contains('saving')) return 'Compte épargne';
    if (t.contains('client')) return 'Profil';
    if (t.contains('transfer')) return 'Transfert';
    return action.isEmpty ? 'Information' : action;
  }

  final int id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? objectType;
}

/// Résumé d'un échéancier simulé avant la demande de prêt.
class LoanSimulation {
  const LoanSimulation({
    required this.installments,
    required this.totalInterest,
    required this.totalRepayment,
  });

  final List<Installment> installments;
  final double totalInterest;
  final double totalRepayment;

  double get monthly => installments.isEmpty ? 0 : installments.first.totalDue;
}
