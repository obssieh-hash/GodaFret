import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/auth/auth_service.dart';
import '../services/pin_service.dart';
import '../services/secure_store.dart';

enum SessionStage { booting, loggedOut, otp, pinSetup, locked, unlocked }

/// Machine à états de la session :
/// connexion → OTP (MFA) → création du PIN → déverrouillée ⇄ verrouillée (PIN).
class SessionController extends ChangeNotifier {
  SessionController({
    required this.config,
    required this.auth,
    required this.pin,
    required this.store,
  });

  final AppConfig config;
  final AuthService auth;
  final PinService pin;
  final SecureStore store;

  SessionStage stage = SessionStage.booting;
  bool busy = false;
  String? error;
  String? info;
  String? otpHint;
  String? lastUsername;
  bool biometricsAvailable = false;
  bool biometricsEnabled = false;
  DateTime? _pausedAt;

  Future<void> init() async {
    lastUsername = await store.read(SecureStore.username);
    biometricsAvailable = await pin.biometricsAvailable();
    biometricsEnabled = await pin.biometricsEnabled();
    final hasPin = await pin.hasPin();
    final hasSession =
        await store.read(SecureStore.refreshToken) != null || await store.read(SecureStore.basicKey) != null;
    stage = hasPin && hasSession ? SessionStage.locked : SessionStage.loggedOut;
    notifyListeners();
  }

  Future<void> login(String username, String password) => _run(() async {
        final result = await auth.login(username.trim(), password);
        lastUsername = username.trim();
        if (result.needsOtp) {
          otpHint = result.otpHint;
          stage = SessionStage.otp;
        } else {
          stage = SessionStage.pinSetup;
        }
      });

  Future<void> verifyOtp(String code) => _run(() async {
        await auth.verifyOtp(code);
        stage = SessionStage.pinSetup;
      });

  Future<void> resendOtp() => _run(() async {
        otpHint = await auth.resendOtp() ?? otpHint;
        info = 'Nouveau code envoyé.';
      });

  void cancelOtp() {
    stage = SessionStage.loggedOut;
    error = null;
    notifyListeners();
  }

  Future<void> createPin(String value, {bool enableBiometrics = false}) => _run(() async {
        await pin.setPin(value);
        if (enableBiometrics && biometricsAvailable) {
          await pin.setBiometricsEnabled(true);
          biometricsEnabled = true;
        }
        stage = SessionStage.unlocked;
      });

  Future<void> changePin(String value) => _run(() => pin.setPin(value));

  /// Retourne `true` si le PIN est correct (utilisé aussi pour confirmer
  /// une opération sensible).
  Future<bool> checkPin(String value) async {
    final res = await pin.verify(value);
    if (res == PinCheck.lockedOut) {
      await _forceLogout('Trop de codes erronés. Reconnectez-vous avec votre mot de passe.');
    }
    return res == PinCheck.ok;
  }

  Future<void> unlockWithPin(String value) => _run(() async {
        final res = await pin.verify(value);
        switch (res) {
          case PinCheck.ok:
            await _restore();
          case PinCheck.wrong:
            final left = await pin.remainingAttempts();
            throw ApiException('Code incorrect. $left essai${left > 1 ? 's' : ''} restant${left > 1 ? 's' : ''}.');
          case PinCheck.lockedOut:
            await _forceLogout('Trop de codes erronés. Reconnectez-vous avec votre mot de passe.');
        }
      });

  Future<void> unlockWithBiometrics() async {
    if (!biometricsEnabled) return;
    if (await pin.authenticateWithBiometrics()) {
      await _run(_restore);
    }
  }

  Future<void> setBiometrics(bool value) async {
    if (value && !await pin.authenticateWithBiometrics()) return;
    await pin.setBiometricsEnabled(value);
    biometricsEnabled = value;
    notifyListeners();
  }

  Future<void> _restore() async {
    if (await auth.restore()) {
      stage = SessionStage.unlocked;
    } else {
      await _forceLogout('Votre session a expiré. Reconnectez-vous.');
    }
  }

  Future<void> logout() async {
    await auth.logout();
    biometricsEnabled = false;
    stage = SessionStage.loggedOut;
    notifyListeners();
  }

  /// Appelé quand Fineract répond 401 : jeton révoqué ou expiré.
  Future<void> onUnauthorized() => _forceLogout('Session expirée. Reconnectez-vous.');

  Future<void> _forceLogout(String message) async {
    await auth.logout();
    biometricsEnabled = false;
    stage = SessionStage.loggedOut;
    error = message;
    notifyListeners();
  }

  // --- Verrouillage automatique -------------------------------------------

  void onPaused() => _pausedAt = DateTime.now();

  void onResumed() {
    final paused = _pausedAt;
    _pausedAt = null;
    if (stage == SessionStage.unlocked && paused != null && DateTime.now().difference(paused) >= config.lockAfter) {
      stage = SessionStage.locked;
      notifyListeners();
    }
  }

  void lockNow() {
    if (stage == SessionStage.unlocked) {
      stage = SessionStage.locked;
      notifyListeners();
    }
  }

  void clearMessages() {
    error = null;
    info = null;
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    info = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = ApiException.from(e).message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
