import '../config/app_config.dart';
import 'secure_store.dart';

/// Serveur choisi dans l'application (écran de connexion › ⚙️).
/// Prioritaire sur la configuration de compilation (--dart-define).
class ServerSettings {
  ServerSettings(this.store);

  final SecureStore store;

  static const _mode = 'server_mode';
  static const _fineract = 'server_fineract_url';
  static const _keycloak = 'server_keycloak_url';
  static const _host = 'server_host';

  Future<AppConfig> apply(AppConfig base) async {
    final mode = await store.read(_mode);
    if (mode == null) return base;
    final authMode = AuthMode.values.firstWhere((m) => m.name == mode, orElse: () => base.authMode);
    return base.copyWith(
      authMode: authMode,
      fineractUrl: await store.read(_fineract),
      keycloakUrl: await store.read(_keycloak),
    );
  }

  Future<String?> host() => store.read(_host);

  Future<void> save({
    required AuthMode mode,
    String? host,
    String? fineractUrl,
    String? keycloakUrl,
  }) async {
    // Changer de serveur invalide la session et le PIN de l'ancien.
    await store.clearSession();
    await store.write(_mode, mode.name);
    await store.write(_host, host);
    await store.write(_fineract, fineractUrl);
    await store.write(_keycloak, keycloakUrl);
  }
}
