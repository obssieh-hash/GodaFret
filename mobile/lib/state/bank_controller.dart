import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/bank_repository.dart';

class MonthStat {
  const MonthStat(this.month, this.income, this.expenses);
  final DateTime month;
  final double income;
  final double expenses;
}

/// Données bancaires du client connecté, partagées par tous les écrans.
class BankController extends ChangeNotifier {
  BankController(this.repo, {this.onUnauthorized});

  final BankRepository repo;
  final Future<void> Function()? onUnauthorized;

  Client? client;
  List<SavingsAccount> savings = const [];
  List<LoanAccount> loans = const [];
  List<LoanAccount> loanDetails = const [];
  List<BankTransaction> history = const [];
  List<AppNotification> notifications = const [];
  bool loading = false;
  String? error;
  DateTime? updatedAt;
  bool balanceHidden = false;

  bool get loaded => client != null;

  String get currency => savings.isNotEmpty ? savings.first.currency : (loans.isNotEmpty ? loans.first.currency : 'EUR');

  double get totalBalance => savings.fold(0, (s, a) => s + a.balance);

  double get totalDebt => loanDetails.where((l) => l.state == LoanState.active).fold(0, (s, l) => s + l.outstanding);

  int get unreadCount => notifications.where((n) => !n.read).length;

  List<LoanAccount> get activeLoans => loanDetails.where((l) => l.state == LoanState.active).toList();

  /// Prochaine échéance tous prêts confondus.
  (LoanAccount, Installment)? get nextInstallment {
    (LoanAccount, Installment)? best;
    for (final l in activeLoans) {
      final i = l.nextInstallment;
      if (i != null && (best == null || i.dueDate.isBefore(best.$2.dueDate))) best = (l, i);
    }
    return best;
  }

  /// Entrées / sorties des comptes épargne sur les [months] derniers mois.
  List<MonthStat> monthlyStats({int months = 6}) {
    final now = DateTime.now();
    return List.generate(months, (k) {
      final m = DateTime(now.year, now.month - (months - 1 - k));
      var income = 0.0;
      var expenses = 0.0;
      for (final t in history) {
        if (t.isLoan || t.date.year != m.year || t.date.month != m.month) continue;
        if (t.amount >= 0) {
          income += t.amount;
        } else {
          expenses += -t.amount;
        }
      }
      return MonthStat(m, income, expenses);
    });
  }

  void toggleBalance() {
    balanceHidden = !balanceHidden;
    notifyListeners();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      client ??= await repo.loadClient();
      final acc = await repo.accounts();
      savings = acc.savings;
      loans = acc.loans;

      final details = await Future.wait(savings.map((a) => repo.savingsDetail(a.id)));
      savings = details.map((d) => d.account).toList();
      loanDetails = await Future.wait(
        loans.map((l) => l.state == LoanState.pending ? Future.value(l) : repo.loanDetail(l.id)),
      );
      history = [
        for (final d in details) ...d.transactions,
        for (final l in loanDetails) ...l.transactions.map((t) => t.withAccountLabel(l.productName)),
      ]..sort((a, b) => b.date.compareTo(a.date));

      try {
        notifications = await repo.notifications();
      } on ApiException catch (e) {
        if (e.isUnauthorized) rethrow;
        notifications = const [];
      }
      updatedAt = DateTime.now();
    } catch (e) {
      final err = ApiException.from(e);
      error = err.message;
      if (err.isUnauthorized) await onUnauthorized?.call();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Exécute une opération puis recharge les données.
  Future<void> perform(Future<void> Function(BankRepository repo) op) async {
    try {
      await op(repo);
    } catch (e) {
      final err = ApiException.from(e);
      if (err.isUnauthorized) await onUnauthorized?.call();
      throw err;
    }
    await refresh();
  }

  Future<void> markNotificationsRead() async {
    try {
      await repo.markNotificationsRead();
      notifications = await repo.notifications();
      notifyListeners();
    } catch (_) {}
  }

  void reset() {
    client = null;
    savings = const [];
    loans = const [];
    loanDetails = const [];
    history = const [];
    notifications = const [];
    error = null;
    updatedAt = null;
    notifyListeners();
  }
}
