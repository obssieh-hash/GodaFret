import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage chiffré (Keychain iOS / Keystore Android).
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const refreshToken = 'kc_refresh_token';
  static const basicKey = 'fineract_basic_key';
  static const tfaToken = 'fineract_tfa_token';
  static const username = 'username';
  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt';
  static const pinAttempts = 'pin_attempts';
  static const biometrics = 'biometrics_enabled';

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String? value) async {
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<void> delete(String key) => _storage.delete(key: key);

  /// Efface la session (jetons), conserve l'identifiant pour pré-remplir.
  Future<void> clearSession() async {
    for (final k in [refreshToken, basicKey, tfaToken, pinHash, pinSalt, pinAttempts, biometrics]) {
      await _storage.delete(key: k);
    }
  }
}
