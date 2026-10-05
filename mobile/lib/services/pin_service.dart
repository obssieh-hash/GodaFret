import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_store.dart';

enum PinCheck { ok, wrong, lockedOut }

/// Code PIN local à 6 chiffres + biométrie facultative.
///
/// Le PIN n'est jamais stocké : seule une empreinte salée (PBKDF-like,
/// SHA-256 itéré) est conservée dans le stockage sécurisé. Après
/// [maxAttempts] erreurs, la session est effacée et une connexion complète
/// (mot de passe + OTP) est exigée.
class PinService {
  PinService(this.store, {LocalAuthentication? localAuth}) : _localAuth = localAuth ?? LocalAuthentication();

  static const pinLength = 6;
  static const maxAttempts = 5;
  static const _iterations = 20000;

  final SecureStore store;
  final LocalAuthentication _localAuth;

  Future<bool> hasPin() async => await store.read(SecureStore.pinHash) != null;

  Future<int> remainingAttempts() async {
    final used = int.tryParse(await store.read(SecureStore.pinAttempts) ?? '0') ?? 0;
    return maxAttempts - used;
  }

  Future<void> setPin(String pin) async {
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await store.write(SecureStore.pinSalt, salt);
    await store.write(SecureStore.pinHash, await compute(_hash, [salt, pin]));
    await store.write(SecureStore.pinAttempts, '0');
  }

  Future<PinCheck> verify(String pin) async {
    final salt = await store.read(SecureStore.pinSalt);
    final expected = await store.read(SecureStore.pinHash);
    if (salt == null || expected == null) return PinCheck.lockedOut;
    final actual = await compute(_hash, [salt, pin]);
    if (_constantTimeEquals(actual, expected)) {
      await store.write(SecureStore.pinAttempts, '0');
      return PinCheck.ok;
    }
    final used = (int.tryParse(await store.read(SecureStore.pinAttempts) ?? '0') ?? 0) + 1;
    await store.write(SecureStore.pinAttempts, '$used');
    return used >= maxAttempts ? PinCheck.lockedOut : PinCheck.wrong;
  }

  /// Refuse les PIN triviaux (000000, 123456, 654321…).
  static String? validateNewPin(String pin) {
    if (pin.length != pinLength) return 'Le code doit contenir $pinLength chiffres.';
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return 'Évitez les chiffres tous identiques.';
    const seq = '0123456789012345';
    const rev = '9876543210987654';
    if (seq.contains(pin) || rev.contains(pin)) return 'Évitez les suites de chiffres.';
    return null;
  }

  // --- Biométrie ---------------------------------------------------------

  Future<bool> biometricsAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> biometricsEnabled() async => await store.read(SecureStore.biometrics) == 'true';

  Future<void> setBiometricsEnabled(bool value) => store.write(SecureStore.biometrics, value ? 'true' : null);

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Déverrouillez GodaFret Banque',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  static String _hash(List<String> args) {
    final salt = utf8.encode(args[0]);
    var digest = sha256.convert([...salt, ...utf8.encode(args[1])]).bytes;
    for (var i = 0; i < _iterations; i++) {
      digest = sha256.convert([...digest, ...salt]).bytes;
    }
    return base64Url.encode(digest);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
