import '../models/models.dart';

class SavingsDetail {
  const SavingsDetail(this.account, this.transactions);
  final SavingsAccount account;
  final List<BankTransaction> transactions;
}

class ClientAccounts {
  const ClientAccounts(this.savings, this.loans);
  final List<SavingsAccount> savings;
  final List<LoanAccount> loans;
}

/// Opérations bancaires exposées à l'interface.
abstract class BankRepository {
  Future<Client> loadClient();
  Future<ClientAccounts> accounts();
  Future<SavingsDetail> savingsDetail(int accountId);
  Future<LoanAccount> loanDetail(int loanId);

  Future<List<PaymentType>> paymentTypes();
  Future<void> deposit(int accountId, double amount, {int? paymentTypeId, String? note});
  Future<void> withdraw(int accountId, double amount, {int? paymentTypeId, String? note});

  /// Recherche un compte épargne bénéficiaire par son numéro.
  Future<Beneficiary> findBeneficiary(String accountNo);
  Future<void> transfer({
    required SavingsAccount from,
    required Beneficiary to,
    required double amount,
    required String description,
  });

  Future<List<LoanProduct>> loanProducts();
  Future<LoanSimulation> simulateLoan(LoanProduct product, double amount, int repayments);
  Future<void> applyForLoan(LoanProduct product, double amount, int repayments, {String? purpose});
  Future<void> repayLoan(int loanId, double amount, {int? paymentTypeId});

  Future<List<AppNotification>> notifications();
  Future<void> markNotificationsRead();
}
