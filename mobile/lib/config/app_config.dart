/// Configuration de l'application, injectée au build avec `--dart-define`.
///
/// Exemple :
/// ```
/// flutter run \
///   --dart-define=AUTH_MODE=keycloak \
///   --dart-define=FINERACT_URL=https://banque.example.com/fineract-provider/api/v1 \
///   --dart-define=KEYCLOAK_URL=https://auth.example.com \
///   --dart-define=KEYCLOAK_REALM=godafret
/// ```
library;

enum AuthMode {
  /// Données fictives en mémoire : l'application fonctionne sans serveur.
  demo,

  /// Keycloak (OpenID Connect) + TOTP, jeton Bearer envoyé à Fineract
  /// (fonction « OIDC Federation » de Fineract).
  keycloak,

  /// Authentification native Fineract (`/authentication`) + 2FA Fineract
  /// (`/twofactor`, code envoyé par e-mail ou SMS).
  fineract,
}

class AppConfig {
  const AppConfig({
    required this.authMode,
    required this.fineractUrl,
    required this.tenant,
    required this.keycloakUrl,
    required this.keycloakRealm,
    required this.keycloakClientId,
    required this.mfaRequired,
    required this.currency,
    required this.lockAfter,
  });

  factory AppConfig.fromEnvironment() {
    const mode = String.fromEnvironment('AUTH_MODE', defaultValue: 'demo');
    return AppConfig(
      authMode: AuthMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => AuthMode.demo,
      ),
      fineractUrl: const String.fromEnvironment(
        'FINERACT_URL',
        defaultValue: 'http://localhost:8082/fineract-provider/api/v1',
      ),
      tenant: const String.fromEnvironment('FINERACT_TENANT', defaultValue: 'default'),
      keycloakUrl: const String.fromEnvironment(
        'KEYCLOAK_URL',
        defaultValue: 'http://localhost:8081',
      ),
      keycloakRealm: const String.fromEnvironment('KEYCLOAK_REALM', defaultValue: 'godafret'),
      keycloakClientId: const String.fromEnvironment(
        'KEYCLOAK_CLIENT_ID',
        defaultValue: 'godafret-mobile',
      ),
      mfaRequired: const bool.fromEnvironment('MFA_REQUIRED', defaultValue: true),
      currency: const String.fromEnvironment('CURRENCY', defaultValue: 'EUR'),
      lockAfter: const Duration(
        seconds: int.fromEnvironment('LOCK_AFTER_SECONDS', defaultValue: 60),
      ),
    );
  }

  final AuthMode authMode;
  final String fineractUrl;
  final String tenant;
  final String keycloakUrl;
  final String keycloakRealm;
  final String keycloakClientId;
  final bool mfaRequired;
  final String currency;

  /// Durée en arrière-plan au-delà de laquelle le code PIN est redemandé.
  final Duration lockAfter;

  bool get isDemo => authMode == AuthMode.demo;

  AppConfig copyWith({AuthMode? authMode, String? fineractUrl, String? keycloakUrl}) => AppConfig(
        authMode: authMode ?? this.authMode,
        fineractUrl: fineractUrl ?? this.fineractUrl,
        tenant: tenant,
        keycloakUrl: keycloakUrl ?? this.keycloakUrl,
        keycloakRealm: keycloakRealm,
        keycloakClientId: keycloakClientId,
        mfaRequired: mfaRequired,
        currency: currency,
        lockAfter: lockAfter,
      );

  /// URLs déduites d'une adresse de serveur installé en réseau local
  /// (`infra/install-local.sh`) : Keycloak sur 8081, API mobile sur 8082.
  /// Une adresse commençant par http(s):// est utilisée telle quelle comme base.
  static ({String fineract, String keycloak}) urlsForHost(String host) {
    var h = host.trim();
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    if (h.startsWith('http://') || h.startsWith('https://')) {
      final uri = Uri.parse(h);
      final base = '${uri.scheme}://${uri.host}';
      return (fineract: '$base:8082/fineract-provider/api/v1', keycloak: '$base:8081');
    }
    final hostOnly = h.split(':').first;
    return (fineract: 'http://$hostOnly:8082/fineract-provider/api/v1', keycloak: 'http://$hostOnly:8081');
  }

  String get keycloakTokenUrl =>
      '$keycloakUrl/realms/$keycloakRealm/protocol/openid-connect/token';

  String get keycloakLogoutUrl =>
      '$keycloakUrl/realms/$keycloakRealm/protocol/openid-connect/logout';

  String get keycloakAccountUrl => '$keycloakUrl/realms/$keycloakRealm/account';
}
