/// Résultat de la première étape de connexion.
class LoginResult {
  const LoginResult.done() : needsOtp = false, otpHint = null;
  const LoginResult.otp({this.otpHint}) : needsOtp = true;

  final bool needsOtp;

  /// Indication affichée sur l'écran OTP (« code envoyé à j***@mail.com »).
  final String? otpHint;
}

/// Contrat commun aux modes d'authentification (démo, Keycloak, Fineract).
abstract class AuthService {
  /// Étape 1 : identifiant + mot de passe.
  Future<LoginResult> login(String username, String password);

  /// Étape 2 : code OTP (MFA).
  Future<void> verifyOtp(String code);

  /// Renvoie un nouveau code (si le mode le permet).
  Future<String?> resendOtp();

  bool get canResendOtp;

  /// Restaure la session enregistrée après déverrouillage par PIN.
  /// Retourne `false` si une reconnexion complète est nécessaire.
  Future<bool> restore();

  /// En-têtes à ajouter aux appels Fineract (jeton rafraîchi si besoin).
  Future<Map<String, String>> authHeaders();

  Future<void> logout();

  String? get username;

  /// Nom complet connu par le fournisseur d'identité (facultatif).
  String? get fullName;

  /// Identifiant du client Fineract s'il est porté par le jeton
  /// (claim `fineract_client_id` dans Keycloak).
  int? get clientIdHint;

  /// Libellé de la méthode MFA, affiché dans l'écran sécurité.
  String get mfaLabel;
}
