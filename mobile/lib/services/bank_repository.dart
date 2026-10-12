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

  /// Recherche un destinataire par numéro de téléphone (client, marchand,
  /// agent) ou par numéro de compte.
  Future<Beneficiary> findRecipient(String query);
  Future<void> transfer({
    required SavingsAccount from,
    required Beneficiary to,
    required double amount,
    required String description,
  });

  Future<List<LoanProduct>> loanProducts();
  Future<LoanSimulation> simulateLoan(LoanProduct product, double amount, int repayments);
  Future<void> applyForLoan(LoanProduct product, double amount, int repayments, {String? purpose});
  /// Rembourse un prêt en débitant un compte du client (virement compte → prêt).
  Future<void> repayLoan(int loanId, double amount, {required SavingsAccount from});

  Future<List<AppNotification>> notifications();
  Future<void> markNotificationsRead();
}
